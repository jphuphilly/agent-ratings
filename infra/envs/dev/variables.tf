variable "region" {
  type    = string
  default = "us-east"
}

variable "k8s_version" {
  type = string
}

variable "api_allowed_cidrs" {
  type = list(string)
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 4
}
