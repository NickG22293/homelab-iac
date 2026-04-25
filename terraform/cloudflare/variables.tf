variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "CloudFlare account ID (found in the dashboard sidebar)"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone ID for nick-gordon.com (found in the domain overview page)"
}

variable "tunnel_name" {
  type    = string
  default = "homelab"
}
