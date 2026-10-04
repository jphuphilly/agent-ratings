output "cluster_id" {
  value = linode_lke_cluster.this.id
}

output "api_endpoints" {
  value = linode_lke_cluster.this.api_endpoints
}

output "kubeconfig" {
  value     = base64decode(linode_lke_cluster.this.kubeconfig)
  sensitive = true
}
