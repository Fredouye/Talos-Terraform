# vSphere
# vsphere_user and vsphere_password are fetched from OpenBao at runtime
# via data.vault_kv_secret_v2.vsphere in providers.tf.
# Store them with: bao kv put kv/talos-dev/vsphere username=... password=...

variable "vsphere_server" {
  type    = string
  default = "vcenter.lab.intra"
}

variable "vsphere_datacenter" {
  type = string
}

variable "vsphere_cluster" {
  type = string
}

variable "vsphere_datastore" {
  type = string
}

variable "vsphere_network" {
  type = string
}

variable "vsphere_folder" {
  type    = string
  default = "Temporaire/Talos"
}

# Separate templates for CPs and workers — different schematic IDs → different OVAs.
variable "vsphere_template_cp" {
  type    = string
  default = "talos-v1.12.2-cp-amd64"
}

variable "vsphere_template_worker" {
  type    = string
  default = "talos-v1.12.2-worker-amd64"
}

# Networking
variable "gateway" {
  type    = string
  default = "192.168.3.254"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.3.254"]
}

variable "ntp_servers" {
  type    = list(string)
  default = ["192.168.3.254"]
}

variable "cluster_vip" {
  type    = string
  default = "192.168.3.40"
}

variable "control_plane_ips" {
  type    = list(string)
  default = ["192.168.3.41", "192.168.3.42", "192.168.3.43"]
}

variable "worker_ips" {
  type    = list(string)
  default = ["192.168.3.44", "192.168.3.45", "192.168.3.46"]
}

variable "node_netmask" {
  type    = number
  default = 24
}

# Interface selector — VMware NICs have MAC addresses starting with 00:50:56.
# Using a deviceSelector instead of interface: "eth0" makes the config
# resilient to interface renaming across Talos upgrades (eth0 → ens192, etc.).
variable "nic_mac_prefix" {
  type    = string
  default = "00:50:56:*"
}

# Cluster
variable "cluster_name" {
  type    = string
  default = "talos-dev"
}

variable "talos_version" {
  type    = string
  default = "v1.12.2"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.34.1"
}

# Schematic IDs from https://factory.talos.dev
# Control planes: talos-vmtoolsd only
# Generate with:
#   curl -sX POST https://factory.talos.dev/schematics \
#     -H "Content-Type: application/yaml" \
#     --data-binary '
#   customization:
#     systemExtensions:
#       officialExtensions:
#         - siderolabs/talos-vmtoolsd'
variable "cp_schematic_id" {
  type    = string
  default = "903b2da78f99adef03cbbd4df6714563823f63218508800751560d3bc3557e40"
}

# Workers: talos-vmtoolsd + iscsi-tools + util-linux-tools (required for Longhorn)
# Generate with:
#   curl -sX POST https://factory.talos.dev/schematics \
#     -H "Content-Type: application/yaml" \
#     --data-binary '
#   customization:
#     systemExtensions:
#       officialExtensions:
#         - siderolabs/talos-vmtoolsd
#         - siderolabs/iscsi-tools
#         - siderolabs/util-linux-tools'
variable "worker_schematic_id" {
  type    = string
  default = ""  # <-- generate and fill in terraform.tfvars before apply
}

# VM sizing — control planes
variable "cp_cpu" {
  type    = number
  default = 2
}

variable "cp_memory" {
  type    = number
  default = 4096
}

variable "cp_disk_gb" {
  type    = number
  default = 40
}

# VM sizing — workers
variable "worker_cpu" {
  type    = number
  default = 4
}

variable "worker_memory" {
  type    = number
  default = 8192
}

variable "worker_disk_gb" {
  type    = number
  default = 80
}

variable "longhorn_disk_gb" {
  type        = number
  default     = 100
  description = "Size in GB of the second disk on worker nodes, dedicated to Longhorn storage (/var/lib/longhorn)."
}

# Rancher
variable "rancher_url" {
  type    = string
  default = "https://rancher.lab.intra"
}
# rancher_token is fetched from OpenBao at runtime via
# data.vault_kv_secret_v2.rancher in providers.tf.
# Store with: bao kv put kv/talos-dev/rancher token=...
