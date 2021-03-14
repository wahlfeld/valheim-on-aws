variable "use_domain" {
  type        = bool
  default     = false
  description = "Whether to create a friendly CNAME that points to the Valheim server"
}

variable "admins" {
  type = map
  default = {}
  description = "List of Valheim server admins (use their SteamID)"
}
