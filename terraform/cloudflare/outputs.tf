output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.homelab.tunnel_token
  sensitive = true
}
