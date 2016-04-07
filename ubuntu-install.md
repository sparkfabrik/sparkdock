apt-get install dnsmasq

Configure dnsmasq with the following file:

```
# Set dns forwarder.
server=/loc/172.17.0.1
server=8.8.4.4
server=8.8.8.8
cache-size=0

# Be a good netizen
# Never forward plain names (without a dot or domain part)
domain-needed
# Never forward addresses in the non-routed address spaces.
bogus-priv

# Only provide DNS and only on loopback
interface=eth0
listen-address=127.0.0.1
no-dhcp-interface=lo0

# Do not serve entires from hosts file
no-hosts
```

`service dnsmasq restart`
`docker run --restart=always -d -v /var/run/docker.sock:/var/run/docker.sock --name dnsdock -p 172.17.0.1:53:53/udp tonistiigi/dnsdock:v1.10.0`




