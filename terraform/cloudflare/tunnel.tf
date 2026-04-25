resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = random_bytes.tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    ingress_rule {
      hostname = "nick-gordon.com"
      service  = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80"
    }
    # Wildcard catch-all — routes *.nick-gordon.com to ingress-nginx, which
    # then dispatches by Host header to the right service.
    ingress_rule {
      hostname = "*.nick-gordon.com"
      service  = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}
