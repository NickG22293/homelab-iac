locals {
  tunnel_cname = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
}

resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = local.tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  content = local.tunnel_cname
  type    = "CNAME"
  proxied = true
}
