# NPM Supply-Chain Detector

This directory hosts a Bash-based scanner that flags compromised npm packages and payload breadcrumbs associated with documented attacks (September 2025 qix incident, Shai-Hulud 2.0, etc.). Indicators are stored under `attacks/` so that new campaigns can be onboarded without rewriting the script.

## Quick Start

```bash
# Scan current directory for all known attacks
/opt/sparkdock/bin/security/npm-supply-chain-detector

# Scan a specific project
/opt/sparkdock/bin/security/npm-supply-chain-detector /path/to/project

# Check for specific attack only
/opt/sparkdock/bin/security/npm-supply-chain-detector -a shai-hulud-2

# List all available attacks
/opt/sparkdock/bin/security/npm-supply-chain-detector --list-attacks
```

## Features

- **Multi-Attack Detection**: Checks for multiple supply chain attacks simultaneously
- **Package Version Scanning**: Detects compromised package versions in package.json, package-lock.json, and yarn.lock
- **Malicious Code Detection**: Scans JavaScript files for known attack signatures
- **Payload Artifact Detection**: Identifies malicious files dropped by attacks
- **Workflow Backdoor Detection**: Checks for malicious GitHub Actions workflows
- **Node.js Optimization**: Uses a Node.js helper for faster dependency parsing when available

## Supported Attacks

### Shai-Hulud 2.0 (November 2025)
- **Date**: November 21-23, 2025
- **Packages**: ~700 compromised packages
- **Targets**: posthog-node, @postman/*, @ensdomains/*, @zapier/* and many others
- **Reference**: [Wiz.io Blog](https://www.wiz.io/blog/shai-hulud-2-0-ongoing-supply-chain-attack)

### September 2025 qix- Account Hijacking
- **Date**: September 8-15, 2025
- **Packages**: ~70 compromised packages
- **Targets**: chalk, ansi-styles, color, debug and related packages

## Usage

### Basic Scanning

```bash
# Scan current directory
npm-supply-chain-detector

# Scan specific directory
npm-supply-chain-detector /path/to/project
```

### Attack Selection

```bash
# Check for all attacks (default)
npm-supply-chain-detector -a all

# Check for Shai-Hulud 2.0 only
npm-supply-chain-detector -a shai-hulud-2

# Check for September 2025 qix attack only
npm-supply-chain-detector -a september-2025-qix
```

### Information Commands

```bash
# Show help
npm-supply-chain-detector --help

# List all available attacks
npm-supply-chain-detector --list-attacks
```

## What Gets Scanned

1. **Package Manifests**:
   - `package.json` - all dependency types (dependencies, devDependencies, etc.)
   - `package-lock.json` - locked versions
   - `yarn.lock` - Yarn lockfile

2. **Installed Packages**:
   - `node_modules/` - checks installed package versions
   - Scopes packages (e.g., `@postman/*`, `@ensdomains/*`)

3. **Source Code**:
   - `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` files
   - Checks for malicious signatures and heavily obfuscated code

4. **Artifacts**:
   - Payload files (e.g., `setup_bun.js`, `cloud.json`)
   - Backdoor workflows (e.g., `.github/workflows/discussion.yaml`)

## Exit Codes

- `0` - No issues found, scan successful
- `1` - Compromised packages or malicious code detected
- `2` - No package manifests found to scan

## Adding New Attacks

To add a new attack signature:

1. **Update `attacks/attacks.json`**:
   ```json
   {
     "id": "new-attack-2025",
     "name": "New Attack 2025",
     "file": "new-attack-2025.txt",
     "date": "2025-12-01",
     "packages": 100,
     "description": "Description of the attack",
     "signatures": ["malicious-signature-1", "malicious-signature-2"],
     "payloadFiles": ["malicious-file.js"],
     "workflowPaths": [".github/workflows/malicious.yaml"]
   }
   ```

2. **Create `attacks/new-attack-2025.txt`**:
   ```bash
   # New Attack 2025 - Compromised Packages
   # Format: ["package-name"]="version"
   ["compromised-package"]="1.2.3"
   ["another-package"]="4.5.6"
   ```

3. **Update the script's case statement** (if needed) in the `load_compromised_packages()` function to handle the new attack ID.

## Architecture

```
bin/security/
├── npm-supply-chain-detector    # Main scanner script
├── scripts/
│   └── list-deps.js              # Node.js helper for dependency extraction
├── attacks/
│   ├── attacks.json              # Attack metadata
│   ├── shai-hulud-2.txt         # Shai-Hulud 2.0 package list
│   └── september-2025-qix.txt   # September 2025 qix attack package list
└── README.md                     # This file
```

## Requirements

- **Bash 4.0+**: Required for associative arrays
- **Node.js** (optional): Enables faster dependency parsing
- **Standard Unix tools**: grep, sed, find, cut

## Performance

- **With Node.js**: Uses optimized dependency parser (~2-5 seconds for medium projects)
- **Without Node.js**: Falls back to grep-based parsing (~5-10 seconds for medium projects)
- **Scan depth**: Default maximum depth of 5 subdirectories (configurable)

## Security Notes

- This tool checks for **known** compromised versions and signatures
- A clean scan does **not** guarantee complete security
- Always run `npm audit` for additional vulnerability checks
- Keep the attack definitions up to date
- Review and investigate any warnings about version ranges

## What to Do If Issues Are Found

1. **Isolate**: Disconnect affected systems from the network
2. **Rotate credentials**: GitHub, cloud providers, npm, API keys
3. **Clean**: Remove node_modules, clear npm cache, reinstall dependencies
4. **Audit**: Review GitHub Actions, commits, and published packages
5. **Report**: Contact security team and relevant package maintainers

## Integration with Sparkdock

This tool is integrated with Sparkdock's task runner (sjust). Use these commands:

```bash
# Run supply chain scan
sjust security-scan-npm

# Scan specific attack
sjust security-scan-npm-attack shai-hulud-2
```

## References

- [Shai-Hulud 2.0 Analysis](https://www.wiz.io/blog/shai-hulud-2-0-ongoing-supply-chain-attack)
- [NPM Security Best Practices](https://docs.npmjs.com/packages-and-modules/securing-your-code)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides)

## License

Part of the Sparkdock project, licensed under GNU General Public License v3.0.
