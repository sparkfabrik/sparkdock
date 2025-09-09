# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Renamed `sparkdock-update-repository` command to `sparkdock-fetch-updates` to better communicate its purpose
- Improved command description: now explains that it fetches latest updates without running system configuration, useful for getting newest sjust recipes and commands without triggering a full system update
- Updated output messages to match new naming: "Fetching latest Sparkdock updates..." and "Sparkdock updates fetched successfully!"