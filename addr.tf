variable "ula_prefix" {
  description = "ULA prefix for services"
  default     = ""
}

variable "unit_name" {
  default = "addr"
}

resource "random_integer" "sd_ula_netnum_1" {
  min = 0
  max = 1048575 # 2^20 - 1
}

resource "random_integer" "sd_ula_netnum_2" {
  min = 0
  max = 1048575 # 2^20 - 1
}

resource "random_integer" "netnum" {
  min = 0
  max = 1048575 # 2^20 - 1
}

locals {
  ula_prefix_src = (var.ula_prefix != "") ? var.ula_prefix : cidrsubnet(cidrsubnet("fd00::/8", 20, random_integer.sd_ula_netnum_1.result), 20, random_integer.sd_ula_netnum_2.result)
  ula_prefix = cidrsubnet(local.ula_prefix_src, 20, random_integer.netnum.result)
}

output "ula_prefix" {
  value = local.ula_prefix
}

output "ipv4_network" {
  value = "127.0.0.0/24"
}

output "ipv6_network" {
  value = local.ula_prefix
}

resource "sys_file" "script" {
  filename        = "/usr/local/bin/${var.unit_name}"
  file_permission = "0755"
  content         = <<EOF
#!/bin/bash

ULA_PREFIX='${local.ula_prefix}'
UNIT_NAME='${var.unit_name}'

${file("${path.module}/addr.sh")}
EOF

  provisioner "local-exec" {
    command = "systemctl daemon-reload"
  }
}

resource "sys_file" "generator" {
  filename        = "/etc/systemd/system-generators/${var.unit_name}"
  file_permission = "0755"
  content         = <<EOF
#!/bin/bash

ULA_PREFIX='${local.ula_prefix}'
UNIT_NAME='${var.unit_name}'
UNIT_TITLE='${replace(title(replace(var.unit_name, "-", " ")), " ", "")}'
BIN="${sys_file.script.filename}"

${file("${path.module}/addr.generator.sh")}
EOF

  provisioner "local-exec" {
    command = "systemctl daemon-reload"
  }
}


resource "sys_file" "loopback6_service" {
  file_permission = "0644"
  filename = "/etc/systemd/system/${var.unit_name}-loopback6.service"
  content = <<EOF
[Unit]
Description=Private loopback IPv6 addresses

[Service]
RemainAfterExit=yes
ExecStart=/usr/sbin/ip addr add '${local.ula_prefix}' dev lo
ExecStop=/usr/sbin/ip addr del '${local.ula_prefix}' dev lo

EOF

  provisioner "local-exec" {
    when    = destroy
    command = "systemctl daemon-reload"
  }
  provisioner "local-exec" {
    command = "systemctl daemon-reload"
  }
}


resource "sys_file" "addr_service" {
  file_permission = "0644"
  filename = "/etc/systemd/system/${var.unit_name}@.service"
  content = <<EOF
[Unit]
Description=Private address provider
Requires=${var.unit_name}-loopback6.service
After=${var.unit_name}-loopback6.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=ULA_PREFIX=${local.ula_prefix}
Environment=UNIT_NAME=${var.unit_name}
Environment=NEW_HOST=%i
ExecStart=${sys_file.script.filename} up %i
ExecStop=${sys_file.script.filename} down %i

EOF

  provisioner "local-exec" {
    when    = destroy
    command = "systemctl daemon-reload"
  }
  provisioner "local-exec" {
    command = "systemctl daemon-reload"
  }
}


