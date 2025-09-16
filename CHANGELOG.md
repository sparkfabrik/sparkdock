# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added `docker-desktop-install-version-4412` task to download Docker Desktop 4.41.2 to work around network issues

### Changed
- Renamed `sparkdock-update-repository` command to `sparkdock-fetch-updates` with improved description and updated output messages
- Lima quick setup now uses dynamic CPU and memory defaults like Docker Desktop: all available processors and 50% of host memory