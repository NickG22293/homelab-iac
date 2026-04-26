# homelab-iac

Infrastructure-as-code for a single-node K3s homelab cluster. Ansible bootstraps the node and installs Flux; Flux then manages everything else via GitOps.

## Architecture

```
Ansible (one-time bootstrap)
  └── Installs K3s on nucbox
  └── Installs Flux CLI + runs flux bootstrap
        └── Flux (continuous GitOps)
              └── clusters/my-cluster/
                    ├── flux-system/     # Flux controllers + Git sync config
                    ├── sealed-secrets/  # Encrypted secrets + registry creds
                    ├── ingress-nginx/   # Ingress controller (NodePort for now)
                    ├── kubed/           # Cross-namespace secret sync
                    └── cloudflared/     # CloudFlare tunnel (exposes cluster to internet)

Terraform (run once, or when DNS/tunnel config changes)
  └── terraform/cloudflare/
        ├── Creates the CloudFlare Tunnel
        ├── Configures ingress routing rules
        └── Creates DNS records (nick-gordon.com + *.nick-gordon.com → tunnel)
```

Flux watches the `main` branch and reconciles the cluster every 10 minutes. Helm releases reconcile every 3–5 minutes.

## Deployed Components

| Component | Purpose |
|-----------|---------|
| K3s | Lightweight Kubernetes (Traefik disabled) |
| Flux v2.5.1 | GitOps continuous deployment |
| Sealed Secrets v2.17.2 | Encrypt secrets safe to commit to Git |
| ingress-nginx v4.12.1 | HTTP/HTTPS ingress (NodePort 32080/32443) |
| Kubed v0.13.2 | Sync secrets/configmaps across namespaces |
| cloudflared 2024.11.1 | CloudFlare Tunnel client — exposes cluster to the internet |

## Getting Back Online

### 1. Rotate the GitHub PAT (it's probably expired)

The Ansible playbook authenticates to GitHub to run `flux bootstrap`. The PAT is stored encrypted in `ansible/secrets.yaml`.

Generate a new PAT at **GitHub → Settings → Developer settings → Personal access tokens**.
It needs `repo` scope (full control of private repositories).

Then update the encrypted secrets file:

```bash
cd ansible
ansible-vault edit secrets.yaml --vault-password-file vault_pass.txt
```

This opens the file in your editor. Update the `github_pat` value and save.

> If you've lost the vault password, you'll need to recreate the secrets file:
> ```bash
> ansible-vault create secrets.yaml --vault-password-file vault_pass.txt
> # Then add: github_pat: "ghp_yournewtokenhere"
> ```

### 2. Ensure prerequisites exist locally

**SSH key** — must exist at `~/.ssh/primary_rsa` and already be authorized on nucbox:
```bash
# If the key is missing, regenerate and copy it:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/primary_rsa -N ""
ssh-copy-id -i ~/.ssh/primary_rsa.pub nick@100.89.219.51
```

**Vault password file** — must exist at `ansible/vault_pass.txt` (not committed to git):
```bash
echo "your-vault-password" > ansible/vault_pass.txt
```

**Tailscale** — nucbox is accessed via Tailscale IP `100.89.219.51`. Make sure your machine is connected to the Tailscale network before running Ansible.

### 3. Run the Ansible playbook

```bash
cd ansible
ansible-playbook install-k3s.yaml -i inventory.yaml
```

This will:
1. Install K3s on nucbox (Traefik disabled)
2. Save the K3s join token to `~/k3s_token.txt` locally
3. Install the Flux CLI
4. Run `flux bootstrap github` — this creates a deploy key in the repo and commits the Flux manifests, then starts reconciling `clusters/my-cluster`

### 4. Verify Flux is running

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml  # on the node, or copy it locally
flux get all
kubectl get pods -n flux-system
```

Flux will pull from GitHub and deploy sealed-secrets, ingress-nginx, and kubed automatically. Allow a few minutes for Helm releases to come up.

## Important: Sealed Secrets After a Full Wipe

Sealed Secrets uses an asymmetric keypair. The **private key lives only on the cluster** — if the cluster was wiped, that key is gone.

The `clusters/my-cluster/sealed-secrets/regcred.yaml` file (the GHCR registry credential) **cannot be decrypted** by a fresh sealed-secrets controller. You'll need to re-seal it:

1. Get the new public key after the controller starts:
   ```bash
   kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=sealed-secrets > pub-cert.pem
   ```

2. Re-create and seal the Docker registry secret:
   ```bash
   kubectl create secret docker-registry regcred \
     --docker-server=ghcr.io \
     --docker-username=NickG22293 \
     --docker-password=<github-pat> \
     --dry-run=client -o yaml | \
   kubeseal --cert pub-cert.pem --format yaml > clusters/my-cluster/sealed-secrets/regcred.yaml
   ```

3. Commit and push — Flux will pick it up.

> To back up the sealing key so you don't have to redo this next time:
> ```bash
> kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
> ```
> Store this somewhere secure (not in this repo).

## CloudFlare Tunnel Setup

Traffic flow: `internet → CloudFlare edge → tunnel → cloudflared pod → ingress-nginx → services`

CloudFlare handles TLS at the edge (Full SSL mode). The tunnel carries plain HTTP internally.

### 1. Create a CloudFlare API token

In the CloudFlare dashboard: **My Profile → API Tokens → Create Token**.

Required permissions:
- `Account > Zero Trust > Edit`
- `Zone > DNS > Edit` (for nick-gordon.com)

### 2. Apply the Terraform

```bash
cd terraform/cloudflare

# Create a tfvars file (gitignored)
cat > terraform.tfvars <<EOF
cloudflare_api_token  = "your-api-token"
cloudflare_account_id = "your-account-id"   # dashboard sidebar
cloudflare_zone_id    = "your-zone-id"       # domain overview page
EOF

terraform init
terraform apply
```

This creates the tunnel, sets routing rules, and creates DNS records for `nick-gordon.com` and `*.nick-gordon.com`.

### 3. Seal the tunnel token as a Kubernetes secret

```bash
# Get the sealing cert (sealed-secrets controller must be running first)
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets > pub-cert.pem

# Get the tunnel token from Terraform and seal it
terraform output -raw tunnel_token | \
  kubectl create secret generic tunnel-credentials \
    --namespace=cloudflared \
    --from-literal=token=$(cat /dev/stdin) \
    --dry-run=client -o yaml | \
  kubeseal --format yaml 
```

Commit and push — Flux will deploy cloudflared and connect the tunnel.

### 4. Verify

```bash
kubectl get pods -n cloudflared
# Both replicas should be Running

kubectl logs -n cloudflared -l app=cloudflared | grep "Registered tunnel"
```

Then hit `https://nick-gordon.com` and it should reach ingress-nginx.

## Making Changes

Any file committed and pushed to `main` under `clusters/my-cluster/` will be automatically applied by Flux within ~10 minutes. Force an immediate sync:

```bash
flux reconcile kustomization flux-system --with-source
```

## Debugging

**K3s service logs (on the node):**
```bash
ssh -i ~/.ssh/primary_rsa nick@100.89.219.51 systemctl status k3s.service
ssh -i ~/.ssh/primary_rsa nick@100.89.219.51 journalctl -xeu k3s.service
```

**Flux reconciliation status:**
```bash
flux get kustomizations
flux get helmreleases -A
flux logs --all-namespaces
```

**Helm release stuck/failing:**
```bash
flux suspend helmrelease <name> -n <namespace>
flux resume helmrelease <name> -n <namespace>
```

## Scaling to Workers (Future)

The Ansible playbook has a commented-out play for joining Raspberry Pi worker nodes. The join token is saved to `~/k3s_token.txt` locally after the master bootstrap. Uncomment the worker play in `ansible/install-k3s.yaml` and update `ansible/inventory.yaml` with worker IPs.
