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

resource "sys_file" "loopback6_service" {
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
Environment=NEW_HOST=%i
ExecStart=/bin/bash -e -c ' \
    if [[ -e /run/mailu-addr/$NEW_HOST.env ]]; then \
      echo "/run/mailu-addr/$NEW_HOST.env: already exists" >&2; \
      exit 0; \
    fi; \
    i=2; \
    prefix=$(echo $ULA_PREFIX | sed 's:/.*::'); \
    while egrep -q "^127.0.0.$i " /etc/hosts; do \
      i=$((i+1)); \
    done; \
    ip4="127.0.0.$i"; \
    ip6="$prefix$(printf %""x $i)"; \
    echo "$ip4 $NEW_HOST $NEW_HOST""4" >>/etc/hosts; \
    echo "$ip6 $NEW_HOST $NEW_HOST""6" >>/etc/hosts; \
    mkdir -p /run/${var.unit_name}; \
    echo "HOST_$(echo $NEW_HOST | sed 's:-:_:g')6=$ip6" >/run/${var.unit_name}/$NEW_HOST.env; \
    echo "HOST_$(echo $NEW_HOST | sed 's:-:_:g')4=$ip4" >>/run/${var.unit_name}/$NEW_HOST.env; \
    ip addr add $ip6 dev lo; \
    '
ExecStop=/bin/bash -e -c ' \
  ip6=$(sed -rn "s/.*6=(.*)/\\\\1/p" /run/${var.unit_name}/$NEW_HOST.env); \
  /usr/bin/sed -ri -e "/^\\\\S* $${NEW_HOST} $${NEW_HOST}[46]$/d" /etc/hosts; \
  /bin/rm -f /run/${var.unit_name}/$${NEW_HOST}.env; \
  ip addr del $ip6 dev lo; \
  '

EOF

  provisioner "local-exec" {
    when    = destroy
    command = "systemctl daemon-reload"
  }
  provisioner "local-exec" {
    command = "systemctl daemon-reload"
  }
}


