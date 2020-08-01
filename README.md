sd-addr.tf
==========

This module is provisionning a systemd service `add@.service` that when running
generates automatically a local IPv4 and IPv6 address using the unit instance
parameter as hostname.

This can be used with containers running with [force-bind] with the host
network. The container can access the Internet because it can access the host
public IP, but it listens on a private network only, and can connect to other
services using hostnames pointing to these local addresses.

Requirements
------------

- [`terraform-provider-sys`](https://github.com/mildred/terraform-provider-sys)
  needs to be manually installed until i split this provider into better suited
  providers.

[force-bind]: https://github.com/mildred/force-bind-seccomp
