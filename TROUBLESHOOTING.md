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

### MacOS quick checks

* Clear the system DNS cache with the following commands:

```
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Ubuntu quick checks

* Check if dnsmasq can actually start or dnsdock is binding port 53 on 0.0.0.0
* Check the other way around
* Check you are running dnsmasq with the default configuration in `/etc/dnsmasq.conf` (you really should use `/etc/dnsmasq.d` to store personal config files!)
* Are your user in the `docker` group?
* Did your read the last notice about loggin' out, then in again to make unix know your user was added to such group?