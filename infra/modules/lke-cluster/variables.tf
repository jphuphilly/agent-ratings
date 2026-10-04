variable "cluster_label" {
  type = string
}

variable "region" {
  type = string
}

variable "k8s_version" {
  type = string
}

variable "node_type" {
  type    = string
  default = "g6-standard-2"
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 4
  validation {
    condition     = var.node_max >= var.node_min
    error_message = "node_max must be >= node_min."
  }
}

variable "ha_control_plane" {
  type    = bool
  default = false
}

variable "api_allowed_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Set at least one CIDR, and do not open the API to 0.0.0.0/0."
  }
}

variable "tags" {
  type    = list(string)
  default = []
}
