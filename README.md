# Sparkdock

This is an automatic MacOSX and Ubuntu Linux Docker provisioner, based on Ansible.

It will install the following packages:

* Install and upgrade docker, docker-machine
* Install and configure dinghy
* Start dnsdock container alongside dnsmasq proxy resolver
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

### Debian

Just issue (tested on Debian stretch 9.1)

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/debian.ubuntu)
```

## Troubleshooting

### General

Please find hints and troubleshooting information on our company playbook: http://playbook.sparkfabrik.com/guides/local-development-environment-configuration

### Error: Cannot link a not running container

With the introduction of docker 1.13, the "exec" command seems to expect that all the containers linked should be in a running state, in order to attach a shell on it.

Maybe you've encountered this problem when using "bin/e": `ERROR: Cannot link to a non running container: /prj_blackfire_agent_1 AS /prj_drupal_1/blackfire`

To fix that, as we are using `blackfire` as a default service, you have to add to your .bashrc/.zshrc, your blackfire configurations tokens, as specified here: https://playbook.sparkfabrik.com/guides/local-development-environment-usage#profiling-with-blackfire-io, to grab your tokens just access this page: https://blackfire.io/account

If something goes awry, please:

### MacOSX quick checks

* Check if dnsmasq is running with `brew services`, to be sure run `brew services restart dnsmasq` then `ps aux | grep dnsmasq` to check if the process is running.
* Check if dnsmasq configurations is equal to: https://github.com/sparkfabrik/sparkdock/blob/master/config/macosx/dnsmasq.conf
* Check if the static routing is still active, to be sure run `sudo route -n add -net 172.16.0.0/12 $(docker-machine ip dinghy)`
* Check if dnsdock container is running `docker ps | grep dnsdock`
* Check dinghy services, you should see something like this:

```
❯ dinghy status
   VM: running
  NFS: running
 FSEV: running
  DNS: stopped
PROXY: stopped

```

### MacOSX filesytem events

With the latest release of sparkdock we introduced the use of the daemon "fsevents_to_vm" (https://github.com/codekitchen/fsevents_to_vm) which is a simple daemon act to migrate osx fsevents filesystem over ssh to the docker-machine, as NFS does not support them.

To check if the daemon is running run `ps aux | grep fsevents_to_vm` if you don't see any process, you can run it again by typing `/usr/local/bin/fsevent-start`.


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
