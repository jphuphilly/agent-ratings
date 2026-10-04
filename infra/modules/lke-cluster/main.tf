resource "linode_lke_cluster" "this" {
  label       = var.cluster_label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = var.tags

  control_plane {
    high_availability = var.ha_control_plane
    acl {
      enabled = true
      addresses {
        ipv4 = var.api_allowed_cidrs
      }
    }
  }

  pool {
    type  = var.node_type
    count = var.node_min
    autoscaler {
      min = var.node_min
      max = var.node_max
    }
  }

  lifecycle {
    ignore_changes = [pool[0].count]
  }
}
