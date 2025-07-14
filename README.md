# Sparkdock

[![Test Ansible Playbook](https://github.com/sparkfabrik/sparkdock/actions/workflows/test-ansible-playbook.yml/badge.svg)](https://github.com/sparkfabrik/sparkdock/actions/workflows/test-ansible-playbook.yml)

This is an automatic MacOS system provisioner, based on Ansible.

## MacOS

It will install the base system, some useful tools and applications, and configure the http-proxy system.

The system automatically clones and configures the [SparkFabrik HTTP Proxy](https://github.com/sparkfabrik/http-proxy) repository, providing `spark-http-proxy` command to manage the HTTP proxy.

The HTTP proxy system includes:

- Automatic DNS configuration for `.loc` domains
- SSL certificate generation via mkcert
- Monitoring with Grafana and Prometheus
- Traefik-based reverse proxy
- Shell completion support

## Installation

To install it, you can run the following command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.macos)
```

## Maintainers

This package is maintained by [SparkFabrik](https://www.sparkfabrik.com)'s staff.

Contributions are welcome, in particular it would be great to have playbooks for other OSes or Linux distro.
Send us PRs, open issues if you encounter bugs, talk about this stuff in your blog and - most important - **use docker!** ;)
