# Sparkdock

This is an automatic MacOS and Ubuntu Linux system provisioner, based on Ansible.

## MacOS

It will install the base system, some useful tools and applications, and some custom scripts.

And some custom scripts you can find under `config/macos/bin`:

1. `run-dingy-proxy`: Custom script to run our docker based http proxy.
1. `ayse-get-sm`: This is a script to print out system informations including serial number.

## Installation

To install it, you can run the following command:

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.macos)
```

## Maintainers

This package is maintained by [SparkFabrik](https://www.sparkfabrik.com)'s staff.

Contributions are welcome, in particular it would be great to have playbooks for other OSes or Linux distro.
Send us PRs, open issues if you encounter bugs, talk about this stuff in your blog and - most important - **use docker!** ;)
