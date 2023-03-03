resource "null_resource" "set_netbox_vm_status_staged" {
  triggers = {
    vm_id = local.netbox_vm_id
  }

  provisioner "local-exec" {
    command = <<EOT
      curl \
        -X PATCH \
        -H "Authorization: Token $NETBOX_API_TOKEN" \
        -H "Content-Type: application/json" \
        $NETBOX_SERVER_URL/api/virtualization/virtual-machines/${self.triggers.vm_id}/ \
        --data '{"status": "staged"}'
    EOT
  }
}

resource "proxmox_vm_qemu" "vm" {
  depends_on = [
    null_resource.set_netbox_vm_status_staged
  ]
  name        = var.name
  bios        = var.bios
  balloon     = local.balloon
  onboot      = var.onboot
  desc        = var.comments
  target_node = var.target_node
  clone       = var.template
  agent       = 1
  memory      = var.memory
  cores       = var.cores
  boot        = "order=${var.boot_order}"
  pool        = "critical"
  qemu_os     = var.qemu_os
  cpu         = var.cpu
  hastate     = var.ha_state == "" ? null : var.ha_state
  hagroup     = var.ha_state == "" ? null : var.ha_group
  scsihw      = var.scsihw

  disk {
    size    = "${var.disk_size}G"
    storage = var.storage
    type    = var.disk_type
    discard = "on"
  }

  network {
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
    tag       = -1
    mtu       = 0
  }

  lifecycle {
    ignore_changes = [args, clone, hagroup, target_node, full_clone]
  }
}


resource "null_resource" "set_static_ip" {
  connection {
    type     = "ssh"
    user     = "packer"
    password = "packer"
    host     = proxmox_vm_qemu.vm.ssh_host
  }

  provisioner "remote-exec" {
    on_failure = continue
    inline = [
      "echo \"network:\" | sudo tee /etc/netplan/00-installer-config.yaml",
      "echo \"  ethernets:\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "echo \"    ens18:\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "echo \"      dhcp4: no\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "echo \"      addresses: [${local.ip_address2}]\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "echo \"      gateway4: 172.29.14.1\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "echo \"      nameservers:\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "echo \"        addresses: [172.29.14.7, 172.29.14.8]\" | sudo tee -a /etc/netplan/00-installer-config.yaml",
      "sudo apt install -y at",
      "echo \"sleep 5s && sudo netplan apply\" | at now"
    ]
  }
}

resource "null_resource" "set_netbox_vm_status" {
  depends_on = [
    proxmox_vm_qemu.vm
  ]

  triggers = {
    vm_id = local.netbox_vm_id
  }

  provisioner "local-exec" {
    command = <<EOT
      curl \
        -X PATCH \
        -H "Authorization: Token $NETBOX_API_TOKEN" \
        -H "Content-Type: application/json" \
        $NETBOX_SERVER_URL/api/virtualization/virtual-machines/${self.triggers.vm_id}/ \
        --data '{"status": "active"}'
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      curl \
        -X PATCH \
        -H "Authorization: Token $NETBOX_API_TOKEN" \
        -H "Content-Type: application/json" \
        $NETBOX_SERVER_URL/api/virtualization/virtual-machines/${self.triggers.vm_id}/ \
        --data '{"status": "decommissioning"}'
    EOT
  }
}
