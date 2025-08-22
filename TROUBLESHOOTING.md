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

#### LaunchAgent Issues

If you encounter "Input/output error" when loading LaunchAgents, this is typically caused by using the deprecated `launchctl load` command on newer macOS versions.

**Symptoms:**
```
$ launchctl load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
Load failed: 5: Input/output error
Try running `launchctl bootstrap` as root for richer errors.
```

**Solution:**
Sparkdock now includes a helper script that automatically uses the modern `launchctl bootstrap` command with fallback to the legacy `launchctl load` for backward compatibility.

**Manual troubleshooting:**
1. Check if the LaunchAgent helper is available:
   ```
   /usr/local/bin/launchctl-helper --help
   ```

2. Try loading manually with detailed output:
   ```
   /usr/local/bin/launchctl-helper load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
   ```

3. Check system logs for LaunchAgent issues:
   ```
   log show --predicate 'subsystem == "com.apple.launchd"' --last 5m
   ```

4. Verify the plist file is valid:
   ```
   plutil -lint ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
   ```

5. Check if the executable exists and is executable:
   ```
   ls -la /usr/local/bin/sparkdock-manager
   ```

**If the issue persists:**
- Restart the LaunchAgent system: `sudo launchctl reboot userspace/$(id -u)`
- Check system security settings that might block the LaunchAgent
- Ensure you have the latest version of Sparkdock with the LaunchAgent fixes

### Ubuntu quick checks

* Check if dnsmasq can actually start or dnsdock is binding port 53 on 0.0.0.0
* Check the other way around
* Check you are running dnsmasq with the default configuration in `/etc/dnsmasq.conf` (you really should use `/etc/dnsmasq.d` to store personal config files!)
* Are your user in the `docker` group?
* Did your read the last notice about loggin' out, then in again to make unix know your user was added to such group?