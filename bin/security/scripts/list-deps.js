#!/usr/bin/env node

/**
 * NPM Dependencies Lister
 * Extracts all dependencies from package.json for supply-chain scanning
 */

const fs = require('fs');
const path = require('path');

function listDependencies(packageJsonPath) {
  try {
    const packageJsonContent = fs.readFileSync(packageJsonPath, 'utf8');
    // Parse with reviver to protect against prototype pollution
    const packageJson = JSON.parse(packageJsonContent, (key, value) => {
      if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
        return undefined;
      }
      return value;
    });
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
    // Log to stderr so the user knows why the fast path failed
    console.error(`Warning: Failed to parse ${packageJsonPath}: ${error.message}`);
    process.exit(0);
  }
}

// Get package.json path from command line argument
const packageJsonPath = process.argv[2] || './package.json';

if (!fs.existsSync(packageJsonPath)) {
  process.exit(0);
}

listDependencies(packageJsonPath);
