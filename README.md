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

To install on MacOSX, no matter which version, issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.macosx)
```

If success, last step is to add on your shell profile file, the following line `eval "$(dinghy env)"`.

Depending on the shell you are using (**HINT**: you can discover it by opening a terminal andh run `echo $SHELL`):

* zsh: `~/.zshrc`
* bash: `~/.bash_profile`


### Ubuntu

We are currently supporting all versions from 14.04 LTS up to 20.04 LTS.  
18.04 support is finally stable (but for docker, read on) and the installation procedure is now totally uninstrusive on systems that ships with `systemd-resolved` (namely 17.04+).  
The new installer automatically selects the correct packages and configurations for your OS version.

**Important note on docker**: due to [some delay in releasing a stable bionic package](https://github.com/docker/for-linux/issues/290) we are relying on `test` official repo channel. This means ATTOW we are running `docker-ce 18.05rc1`. If you experience any issue, please change your repository back to `artful stable`.  
Stable support will be available as soon as available (probably in june 2018).

To install just issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.ubuntu)
```

### Debian

The provisioner has been tested on Debian Stretch 9.1 only. With newer versions YMMV. To install on Debian, issue

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/bin/install.debian)
```

### Windows

The provisioner scripts work only on Windows 10 Pro or Enterprise edition from the version 2004. To install all features, you should clone the sparkdock and after it, you should run Windows PowerShell as an Administrator. Then you can run two scripts in this way:

```
powershell.exe -noprofile -executionpolicy bypass -file .\EnableHyperVAndWsl.ps1
```

and after your pc is restarted

```
powershell.exe -noprofile -executionpolicy bypass -file .\ConfigureLocalDevEnv.ps1
```

After your pc is restarted, you open Ubuntu 20.04 and create your user. All you need to do is insert your username and password.

![Alt Text](/windows/docs/ubuntuCredentials.png)

Don't forget to install docker and other stuff in Ubuntu:

```
bash <(curl -fsSL https://raw.githubusercontent.com/sparkfabrik/sparkdock/master/windows/bin/install.ubuntu)
```

Then you should configure properly docker desktop in this way:

![Alt Text](/windows/docs/useWsl2.png)

![Alt Text](/windows/docs/wslIntegration.png)

## Troubleshooting

### General

Please find hints and troubleshooting information on our company playbook: http://playbook.sparkfabrik.com/guides/local-development-environment-configuration

### Linux

#### Clear the DNS cache or restart systemd-resolved

Open a terminal and run: 

```
systemctl restart systemd-resolved
```

To check the status of `systemd-resolved` run: `resolvectl status` from the command line and you 
should see something like this:

```
Global
       LLMNR setting: no                  
MulticastDNS setting: no                  
  DNSOverTLS setting: no                  
      DNSSEC setting: no                  
    DNSSEC supported: no                  
  Current DNS Server: 172.17.0.1          
         DNS Servers: 172.17.0.1          
          DNS Domain: ~loc                
          DNSSEC NTA: 10.in-addr.arpa     
                      16.172.in-addr.arpa 
                      168.192.in-addr.arpa
                      17.172.in-addr.arpa 
                      18.172.in-addr.arpa 
                      19.172.in-addr.arpa 
                      20.172.in-addr.arpa 
```

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
* Clear the system DNS cache with the following commands:

```
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
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

### Windows tips

Don’t install or clone anything in the mnt/c default folder. It’s better for the performance if you use the Linux filesystem and not the folder that Windows mounts into your Linux distribution

When you clone some project with one or more containers, remember to check if the docker-compose.yml file has VIRTUAL_HOST='alias/aliases of my application/applications' as param of environments section of your service, if it doesn't, add the docker-compose.override.yml file with this param.
For more details about the use of VIRTUAL_HOST go to this site: https://github.com/codekitchen/dinghy-http-proxy

If you add the VIRTUAL_HOST you should change your hosts file on Windows. For example: 

```
VIRTUAL_HOST=myapp.loc
```

You should run this command in powershell to add the alias myapp.loc to your hosts file

```
Set-CHostsEntry -IPAddress 127.0.0.1 -HostName 'myapp.loc'
```

If you encounter these errors in Ubuntu you can solve them with few steps.

* ERROR: Couldn’t connect to Docker daemon at http+docker://localunixsocket – is it running?

```
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
sudo service docker start
```

* Service ‘app’ failed to build: cgroups: cannot find cgroup mount destination: unknown

```
sudo mkdir /sys/fs/cgroup/system
sudo mount -t cgroup -o none,name=system cgroup /sys/fs/cgroup/system
```

## Maintainer

This package is maintained by [SparkFabrik](https://www.sparkfabrik.com)'s staff, mostly by Paolo Mainardi (MacOSX configuration) and Paolo Pustorino (Ubuntu configuration).

Contributions are welcome, in particular it would be great to have playbooks for other OSes or Linux distro.
Send us PRs, open issues if you encounter bugs, talk about this stuff in your blog and - most important - **use docker!** ;)
