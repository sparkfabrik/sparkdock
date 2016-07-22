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

# OSX Troubleshooting
* Check if dnsmasq is running with `brew services`, to be sure run `brew services restart dnsmasq`
* Check if dnsmasq configurations is equal to: https://github.com/sparkfabrik/sparkdock/blob/master/config/osx/dnsmasq.conf
* Check if the static routing is still active, to be sure run `sudo route -n add -net 172.17.0.0 $(docker-machine ip dev)`
* Check if dnsdock container is running `docker ps | grep dnsdock`
