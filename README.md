# Sparkdock

This is an automatic MacOSX and Ubuntu Linux Docker provisioner, based on Ansible.

It will install the following packages:

* Create and start a standard docker dev machine
* Start dnsdock container alongside dnsmasq proxy resolver
* Docker toolbox (MacOSX only)
* Install and configure docker-machine-nfs (MacOSX only)
* Install a launchscript to automatically start the docker vm (MacOSX only)

##

## Installation

### MacOSX

Just issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.macosx)
```

### Ubuntu

Just issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.ubuntu)
```

## Troubleshooting

### General

Please find hints and troubleshooting information on our company playbook: http://playbook.sparkfabrik.com/guides/local-development-environment-configuration

If something goes awry, please:

### MacOSX quick checks

* Check if dnsmasq is running with `brew services`, to be sure run `brew services restart dnsmasq`
* Check if dnsmasq configurations is equal to: https://github.com/sparkfabrik/sparkdock/blob/master/config/osx/dnsmasq.conf
* Check if the static routing is still active, to be sure run `sudo route -n add -net 172.17.0.0 $(docker-machine ip dev)`
* Check if dnsdock container is running `docker ps | grep dnsdock`

### Ubuntu quick checks

* Check if dnsmasq can actually start or dnsdock is binding port 53 on 0.0.0.0
* Check the other way around
* Check you are running dnsmasq with the default configuration in `/etc/dnsmasq.conf` (you really should use `/etc/dnsmasq.d` to store personal config files!)
* Are your user in the `docker` group?
* Did your read the last notice about loggin' out, then in again to make unix know your user was added to such group?

## Maintainer

This package is maintained by [SparkFabrik](https://www.sparkfabrik.com)'s staff, mostly by Paolo Mainardi (MacOSX configuration) and Paolo Pustorino (Ubuntu configuration).

Contributions are welcome, in particular it would be great to have playbooks for other OSes or Linux distro.  
Send us PRs, open issues if you encounter bugs, talk about this stuff in your blog and - most important - **use docker!** ;)
