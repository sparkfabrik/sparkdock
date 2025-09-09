## Troubleshooting

### General

Please find hints and troubleshooting information on our company playbook: http://playbook.sparkfabrik.com/guides/local-development-environment-configuration

### System Requirements

**Supported macOS Versions:**
- macOS Sonoma (14.x)
- macOS Sequoia (15.x)

**Prerequisites:**
- Administrator privileges required for installation
- Stable internet connection for downloading packages
- At least 5GB free disk space for development tools
- Homebrew will be installed automatically if not present

### SparkJust (sjust) Commands

Sparkdock includes the `sjust` task runner for common development tasks. If you encounter issues:

**Check available commands:**
```bash
sjust                    # Show welcome message and basic info
sjust --list             # List all available tasks
```

**Common sjust commands:**
```bash
sjust system-device-info      # Display system information
sjust docker-ps              # Show running Docker containers
sjust system-upgrade         # Update Homebrew packages
sjust http-proxy-start       # Start the HTTP proxy system
sjust http-proxy-stop        # Stop the HTTP proxy system
```

**Custom tasks:**
Add your own tasks to `~/.config/sjust/100-custom.just` for project-specific automation.

### Docker Desktop Network Issues

Docker Desktop can experience network connectivity issues that affect containerized applications. Sparkdock provides sjust commands to resolve common network problems:

#### UDP Networking Issues

If you experience UDP connectivity problems with containers:

**Enable kernel networking for UDP (may not be compatible with VPN software):**
```bash
sjust docker-desktop-enable-kernel-udp
```

**Disable kernel networking for UDP:**
```bash
sjust docker-desktop-disable-kernel-udp
```

#### Host Networking Issues

When containers need to access localhost services on the host:

**Enable host networking:**
```bash
sjust docker-desktop-enable-host-networking
```

**Disable host networking:**
```bash
sjust docker-desktop-disable-host-networking
```

#### General Docker Desktop Issues

**Restart Docker Desktop to resolve common issues:**
```bash
sjust docker-desktop-restart
```

**Note:** These settings are automatically backed up before changes are made. If you experience issues after enabling these features, you can disable them using the corresponding disable commands.

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

### Common Sparkdock Issues

#### Installation Problems

**Permission errors during installation:**
- Ensure you have administrator privileges on your macOS system
- Installation requires `sudo` access for some system modifications

**Network connectivity issues:**
- Check your internet connection
- Verify access to GitHub and Homebrew repositories
- Some corporate networks may block required domains

**Lock file issues:**
If Sparkdock appears to be stuck or reports lock file errors:
```bash
rm -f /tmp/sparkdock.lock
```

#### Update Problems

**Failed updates:**
- Sparkdock automatically rolls back failed updates
- Check `/opt/sparkdock` directory exists and has proper permissions
- Ensure git repository in `/opt/sparkdock` is in a clean state

**Menu bar app not updating:**
```bash
sjust menubar          # Restart the menu bar app manually
```

#### HTTP Proxy Issues

**Proxy services not starting:**
```bash
spark-http-proxy status    # Check service status
spark-http-proxy restart   # Restart all proxy services
```

**`.loc` domains not resolving:**
- Verify DNS resolver configuration in `/etc/resolver/loc`
- Clear DNS cache (see macOS DNS troubleshooting below)
- Restart the HTTP proxy system

#### Package Installation Issues

**Homebrew formula conflicts:**
```bash
sjust system-upgrade      # Update all Homebrew packages
brew doctor               # Check for Homebrew issues
```

**Cask installation failures:**
- Some casks require manual intervention or have specific system requirements
- Check the specific error message and consult Homebrew cask documentation

### MacOS Quick Checks

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