output "talosconfig" {
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
  description = "talosctl config — save to ~/.talos/config"
}

output "kubeconfig" {
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
  description = "kubectl config — save to ~/.kube/talos-dev.yaml"
}

output "cluster_vip" {
  value = var.cluster_vip
}

output "control_plane_ips" {
  value = var.control_plane_ips
}

output "worker_ips" {
  value = var.worker_ips
}

output "rancher_cluster_id" {
  value = rancher2_cluster.talos_lab.id
}

output "cp_schematic_id" {
  value = var.cp_schematic_id
}

output "worker_schematic_id" {
  value = var.worker_schematic_id
}
