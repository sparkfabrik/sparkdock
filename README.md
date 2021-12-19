# Sparkdock

This is an automatic MacOS and Ubuntu Linux system provisioner, based on Ansible.

## MacOS

It will install the following packages:

### System and cloud native packages

### Docker
1. docker (for mac)
1. docker-completion
1. docker-compose
1. docker-credential-helper-ecr

### Cloud native

1. google-cloud-sdk
1. kubernetes-cli
1. kind
1. awscli

### System utilities
1. neofetch
1. gpg
1. yadm
1. iterm2

### Productivity
1. toggl-track
1. slack
1. zoom

### Development
1. visual-studio-code
1. node@16
1. yarn
1. yarn-completion
1. php@8.0
1. golang

And some custom scripts you can find under `config/macos/bin`:

1. `run-dingy-proxy`: Custom script to run our docker based http proxy.
1. `ayse-get-sm`: This is a script to print out system informations including serial number.

## Ubuntu

> Please note: The Ubuntu provisioner here is almost deprecated, we are going to replace it
  with a custom Ubuntu provisioner repository which will includes way more options.

Right now it just install `docker` + `docker-compose` + all needed to develop, including
`dnsdock` and our custom `dingy-proxy`.

## Installation

### MacOS

To install on MacOS, issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.macos)
```

### Ubuntu

We are currently supporting only 20.04 LTS.

To install just issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.ubuntu)
```

## Maintainer

This package is maintained by [SparkFabrik](https://www.sparkfabrik.com)'s staff, mostly by Paolo Mainardi (macos configuration) and Paolo Pustorino (Ubuntu configuration).

Contributions are welcome, in particular it would be great to have playbooks for other OSes or Linux distro.
Send us PRs, open issues if you encounter bugs, talk about this stuff in your blog and - most important - **use docker!** ;)
