# Sparkdock

This is an automatic MacOSX and Ubuntu Linux Docker provisioner, based on ansible.

It will install the following packages:

* Docker toolbox
* Create and start a standard docker dev machine
* Install and configure docker-machine-nfs
* Start dnsdock container
* Install a launchscript to automatically the docker vm

# Installation

## MacOSX

Just issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/bootstrap)
```

## Ubuntu

We lied about the availability for Linux but it will soon be available, promise!

In the meantime, follow this guide to do it by hand: http://playbook.sparkfabrik.com/guides/local-development-environment-configuration

# Troubleshooting

## MacOSX

* Check if dnsmasq is running with `brew services`, to be sure run `brew services restart dnsmasq`
* Check if dnsmasq configurations is equal to: https://github.com/sparkfabrik/sparkdock/blob/master/config/osx/dnsmasq.conf
* Check if the static routing is still active, to be sure run `sudo route -n add -net 172.17.0.0 $(docker-machine ip dev)`
* Check if dnsdock container is running `docker ps | grep dnsdock`
