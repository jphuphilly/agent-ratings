output "cluster_id" {
  value = module.cluster.cluster_id
}

output "api_endpoints" {
  value = module.cluster.api_endpoints
}

output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}
