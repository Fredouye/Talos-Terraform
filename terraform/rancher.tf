# ─── Kubernetes provider (for Rancher registration manifest) ──────────────────

provider "kubernetes" {
  host                   = "https://${var.cluster_vip}:6443"
  client_certificate     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
  client_key             = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
  cluster_ca_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
}

# ─── 1. Generic import cluster stub in Rancher ────────────────────────────────
#
# Use rancher2_cluster (v1 API) with no driver config for generic import.
# rancher2_cluster_v2 is for RKE2/k3s clusters provisioned by Rancher — it
# always injects an rkeConfig that the Rancher webhook rejects for non-RKE clusters.
#
# If you get a 422 NotUnique error, the cluster already exists from a previous
# apply. Either delete it in Rancher UI, or import it:
#   terraform import rancher2_cluster.talos_lab <cluster-id>

resource "rancher2_cluster" "talos_lab" {
  name        = var.cluster_name
  description = "Talos Linux on vSphere"

  lifecycle {
    ignore_changes = [description]
  }
}

# ─── 2. Apply the Rancher registration manifest ───────────────────────────────

resource "null_resource" "rancher_registration" {
  triggers = {
    manifest_url = rancher2_cluster.talos_lab.cluster_registration_token[0].manifest_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "${talos_cluster_kubeconfig.this.kubeconfig_raw}" > /tmp/talos-dev-kubeconfig.yaml
      chmod 600 /tmp/talos-dev-kubeconfig.yaml

      kubectl --kubeconfig /tmp/talos-dev-kubeconfig.yaml \
        apply -f "${rancher2_cluster.talos_lab.cluster_registration_token[0].manifest_url}" \
        --insecure-skip-tls-verify

      rm -f /tmp/talos-dev-kubeconfig.yaml
    EOT
  }

  depends_on = [data.talos_cluster_health.this]
}
