# Setup passwordless SSH on Nodes

Generate keypair locally: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/primary_rsa -N ""`

Copy ssh key to the Node: `ssh-copy-id -i ~/.ssh/primary_rsa.pub nick@<node_ip>`

Enable passwordless sudo for the user nick on the nodes via visudo 

# Setup Ansible Vault password file 

Create a file called "vault_pass.txt" with the appropriate password for this Ansible Vault

# Run Ansible 

`ansible-playbook install-k3s.yaml -i inventory.yaml`

# Debugging Tips 

## K3s 

If something goes wrong during a k3s install, Ansible isn't the best at returning why. Use system services in Linux for debugging: 

`ssh -i ~/.ssh/primary_rsa nick@<node_ip> systemctl status k3s.service`
`ssh -i ~/.ssh/primary_rsa nick@<node_ip> journalctl -xeu k3s.service`