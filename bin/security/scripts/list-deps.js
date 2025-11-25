#!/usr/bin/env node

/**
 * NPM Dependencies Lister
 * Extracts all dependencies from package.json for supply-chain scanning
 */

const fs = require('fs');
const path = require('path');

function listDependencies(packageJsonPath) {
  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    const deps = new Map();

    // Collect all types of dependencies
    const depTypes = [
      'dependencies',
      'devDependencies',
      'peerDependencies',
      'optionalDependencies'
    ];

    depTypes.forEach(depType => {
      if (packageJson[depType]) {
        Object.entries(packageJson[depType]).forEach(([pkg, version]) => {
          // Store the first version we encounter (dependencies take precedence)
          if (!deps.has(pkg)) {
            deps.set(pkg, version);
          }
        });
      }
    });

    // Output in format that bash can easily parse: package<TAB>version
    deps.forEach((version, pkg) => {
      console.log(`${pkg}\t${version}`);
    });
  } catch (error) {
    // Silent failure - bash script will fall back to grep
    process.exit(0);
  }
}

// Get package.json path from command line argument
const packageJsonPath = process.argv[2] || './package.json';

if (!fs.existsSync(packageJsonPath)) {
  process.exit(0);
}

listDependencies(packageJsonPath);
