# ─── Data sources ─────────────────────────────────────────────────────────────

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "ds" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "net" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Separate templates for control planes and workers — they use different
# schematic IDs and therefore different OVAs.
data "vsphere_virtual_machine" "template_cp" {
  name          = var.vsphere_template_cp
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template_worker" {
  name          = var.vsphere_template_worker
  datacenter_id = data.vsphere_datacenter.dc.id
}

# ─── VM folder ────────────────────────────────────────────────────────────────
# Use a data source rather than a resource so Terraform does not attempt to
# create the folder if it already exists in vCenter.
# The data source path is absolute (/<datacenter>/vm/<path>) — used only for
# validation. VM resources use var.vsphere_folder (relative) to avoid the
# vsphere provider doubling the path.

data "vsphere_folder" "k8s" {
  path = "/${var.vsphere_datacenter}/vm/${var.vsphere_folder}"
}

# ─── Control Planes ───────────────────────────────────────────────────────────

resource "vsphere_virtual_machine" "control_planes" {
  count            = length(var.control_plane_ips)
  name             = "${var.cluster_name}-cp-0${count.index + 1}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.ds.id
  # Use the relative path — vsphere_virtual_machine.folder expects a path
  # relative to the datacenter. data.vsphere_folder.k8s.path is absolute
  # and causes the datacenter segment to be doubled.
  folder           = var.vsphere_folder
  num_cpus         = var.cp_cpu
  memory           = var.cp_memory
  guest_id         = data.vsphere_virtual_machine.template_cp.guest_id
  firmware         = "efi"
  enable_disk_uuid = true

  # Talos uses talos-vmtoolsd, not open-vm-tools. It only reports an IP to
  # vCenter after the full install+reboot cycle (~2-3 min). Without these set
  # to 0 the vsphere provider times out waiting for an IP address.
  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0

  clone {
    template_uuid = data.vsphere_virtual_machine.template_cp.id
  }

  network_interface {
    network_id     = data.vsphere_network.net.id
    adapter_type   = data.vsphere_virtual_machine.template_cp.network_interface_types[0]
    use_static_mac = true
    mac_address    = local.control_plane_macs[count.index]
  }

  disk {
    label            = "disk0"
    size             = var.cp_disk_gb
    thin_provisioned = true
  }

  # The real machine config is injected at VM creation time via guestinfo.
  # base64encode() produces a single encoding pass. The vsphere provider passes
  # the string as-is to the VMware API; Talos decodes it using the encoding key.
  # This avoids the "illegal base64 data" error caused by double-encoding.
  extra_config = {
    "guestinfo.talos.config"          = base64encode(data.talos_machine_configuration.cp[count.index].machine_configuration)
    "guestinfo.talos.config.encoding" = "base64"
    "disk.enableUUID"                 = "TRUE"
  }

  lifecycle {
    # Talos writes config to disk on first boot and never re-reads guestinfo.
    # Ignoring changes prevents Terraform from force-replacing the VM on re-apply.
    ignore_changes = [
      extra_config,
      clone,
    ]
  }

  depends_on = [data.talos_machine_configuration.cp]
}

# ─── Workers ──────────────────────────────────────────────────────────────────

resource "vsphere_virtual_machine" "workers" {
  count            = length(var.worker_ips)
  name             = "${var.cluster_name}-wk-0${count.index + 1}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.ds.id
  folder           = var.vsphere_folder
  num_cpus         = var.worker_cpu
  memory           = var.worker_memory
  guest_id         = data.vsphere_virtual_machine.template_worker.guest_id
  firmware         = "efi"
  enable_disk_uuid = true

  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0

  clone {
    template_uuid = data.vsphere_virtual_machine.template_worker.id
  }

  network_interface {
    network_id     = data.vsphere_network.net.id
    adapter_type   = data.vsphere_virtual_machine.template_worker.network_interface_types[0]
    use_static_mac = true
    mac_address    = local.worker_macs[count.index]
  }

  disk {
    label            = "disk0"
    size             = var.worker_disk_gb
    thin_provisioned = true
  }

  # Second disk dedicated to Longhorn storage.
  # Partitioned, formatted (XFS), and mounted at /var/lib/longhorn by Talos
  # via machine.disks in the worker machine config patch.
  disk {
    label            = "disk1"
    size             = var.longhorn_disk_gb
    unit_number      = 1
    thin_provisioned = true
  }

  extra_config = {
    "guestinfo.talos.config"          = base64encode(data.talos_machine_configuration.worker[count.index].machine_configuration)
    "guestinfo.talos.config.encoding" = "base64"
    "disk.enableUUID"                 = "TRUE"
  }

  lifecycle {
    ignore_changes = [
      extra_config,
      clone,
    ]
  }

  depends_on = [data.talos_machine_configuration.worker]
}
