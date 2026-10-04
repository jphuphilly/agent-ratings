module "cluster" {
  source = "../../modules/lke-cluster"

  cluster_label     = "agent-ratings-dev"
  region            = var.region
  k8s_version       = var.k8s_version
  node_type         = "g6-standard-2"
  node_min          = var.node_min
  node_max          = var.node_max
  ha_control_plane  = false
  api_allowed_cidrs = var.api_allowed_cidrs
  tags              = ["agent-ratings", "env:dev", "managed-by:terraform"]
}
