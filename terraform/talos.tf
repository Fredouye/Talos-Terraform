# ─── 1. Machine secrets (PKI, tokens, encryption keys) ────────────────────────
#
# Generated once on first apply, stored in Terraform state.
# Treat the state file as a secret — it contains the cluster root CA.

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# ─── 2. Control plane machine configurations ──────────────────────────────────

data "talos_machine_configuration" "cp" {
  count              = length(var.control_plane_ips)
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = "https://${var.cluster_vip}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    # Patch 1 — v1alpha1 machine config
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = "factory.talos.dev/installer/${var.cp_schematic_id}:${var.talos_version}"
        }
        time = {
          disabled = false
          servers  = var.ntp_servers
        }
        network = {
          # hostname is set via HostnameConfig document below (Talos 1.12+).
          # Setting hostname here conflicts with the provider-generated
          # HostnameConfig auto: stable document and causes a validation error.
          #
          # deviceSelector replaces interface: "eth0" — VMware NIC names are
          # not stable across upgrades (eth0 may become ens192). Matching by
          # MAC prefix is resilient to interface renaming.
          interfaces = [
            {
              deviceSelector = {
                hardwareAddr = var.nic_mac_prefix
              }
              addresses = ["${var.control_plane_ips[count.index]}/${var.node_netmask}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              # The VIP floats across all control plane nodes using ARP.
              # Declare it on every CP — Talos arbitrates who holds it.
              vip = {
                ip = var.cluster_vip
              }
            }
          ]
          nameservers = var.dns
        }
        features = {
          hostDNS = {
            enabled              = true
            forwardKubeDNSToHost = true
          }
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        adminKubeconfig = {
          certLifetime = "87600h"
        }
      }
    }),
    # Patch 2 — HostnameConfig (Talos 1.12+ multi-doc format).
    # The Terraform provider emits `auto: stable` by default. Setting
    # `auto: off` alongside `hostname` overrides it without conflicting.
    # Cannot use $patch: replace — the provider rejects unknown keys.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = "${var.cluster_name}-cp-0${count.index + 1}"
    }),
  ]
}

# ─── 3. Worker machine configurations ─────────────────────────────────────────

data "talos_machine_configuration" "worker" {
  count              = length(var.worker_ips)
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = "https://${var.cluster_vip}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          # Workers use a different schematic — talos-vmtoolsd + iscsi-tools
          # + util-linux-tools for Longhorn support.
          image = "factory.talos.dev/installer/${var.worker_schematic_id}:${var.talos_version}"
        }
        time = {
          disabled = false
          servers  = var.ntp_servers
        }
        network = {
          interfaces = [
            {
              deviceSelector = {
                hardwareAddr = var.nic_mac_prefix
              }
              addresses = ["${var.worker_ips[count.index]}/${var.node_netmask}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
          nameservers = var.dns
        }
        # Partition, format (XFS), and mount the second disk at /var/lib/longhorn.
        # size: "0" means use all available space on the partition.
        # Talos enforces a minimum XFS volume size of 300Mi — not a concern here.
        disks = [
          {
            device = "/dev/sdb"
            partitions = [
              {
                mountpoint = "/var/lib/longhorn"
                size       = "0"
              }
            ]
          }
        ]
        # Propagate the /var/lib/longhorn mount into the kubelet namespace so
        # Longhorn can discover and use the volume.
        kubelet = {
          extraMounts = [
            {
              destination = "/var/lib/longhorn"
              type        = "bind"
              source      = "/var/lib/longhorn"
              options     = ["bind", "rshared", "rw"]
            }
          ]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = "${var.cluster_name}-wk-0${count.index + 1}"
    }),
  ]
}

# ─── 4. talosctl client configuration ─────────────────────────────────────────

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = var.control_plane_ips
  endpoints            = var.control_plane_ips
}

# ─── 5. Bootstrap etcd on the first control plane ─────────────────────────────
#
# VMs boot, install Talos from guestinfo, reboot, then listen on port 50000.
# This resource triggers etcd initialisation on cp-01 only. cp-02 and cp-03
# join the etcd cluster automatically via the discovery token in the machine config.
# The provider retries until the node is reachable after install+reboot.

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_ips[0]
  endpoint             = var.control_plane_ips[0]

  depends_on = [vsphere_virtual_machine.control_planes]
}

# ─── 6. Wait for cluster health ───────────────────────────────────────────────

data "talos_cluster_health" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = var.control_plane_ips
  worker_nodes         = var.worker_ips
  endpoints            = var.control_plane_ips

  timeouts = {
    read = "15m"
  }

  depends_on = [
    talos_machine_bootstrap.this,
    vsphere_virtual_machine.workers,
  ]
}

# ─── 7. Retrieve kubeconfig ───────────────────────────────────────────────────

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_ips[0]
  endpoint             = var.control_plane_ips[0]

  depends_on = [data.talos_cluster_health.this]
}

# ─── 8. Label worker nodes ────────────────────────────────────────────────────
#
# node-role.kubernetes.io/worker cannot be set via kubelet --node-labels in
# Kubernetes 1.27+ — labels in the kubernetes.io namespace must begin with
# kubelet.kubernetes.io or node.kubernetes.io, or be in the allowed set.
# kubelet.nodeLabels is rejected by the Terraform provider schema.
# Solution: apply the label post-bootstrap via kubectl.

resource "null_resource" "worker_labels" {
  triggers = {
    worker_ips = join(",", var.worker_ips)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "${talos_cluster_kubeconfig.this.kubeconfig_raw}" > /tmp/talos-dev-label-kubeconfig.yaml
      chmod 600 /tmp/talos-dev-label-kubeconfig.yaml

      %{for i, ip in var.worker_ips~}
      kubectl --kubeconfig /tmp/talos-dev-label-kubeconfig.yaml \
        label node ${var.cluster_name}-wk-0${i + 1} \
        node-role.kubernetes.io/worker="" \
        --overwrite
      %{endfor~}

      rm -f /tmp/talos-dev-label-kubeconfig.yaml
    EOT
  }

  depends_on = [talos_cluster_kubeconfig.this]
}
