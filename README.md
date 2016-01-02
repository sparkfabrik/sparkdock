# Sparkdock

This is an automatic osx docker provisioner, based on ansible.

It will install the following packages:

* Docker toolbox
* Create and start a standard docker dev machine
* Install and configure docker-machine-nfs
* Start dnsdock container
* Install a launchscript to automatically the docker vm

# Installation

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/bootstrap)
```