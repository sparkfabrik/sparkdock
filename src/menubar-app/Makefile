# Makefile for Sparkdock Menu Bar App

.PHONY: build install uninstall clean test dev check-swiftly

# Build with the pinned toolchain; retry with the native backend if needed.
build: check-swiftly
	@swiftly run swift build -c release || { \
		echo "swiftly run swift build failed; retrying with the native build system"; \
		swiftly run swift build -c release --build-system native; \
	}
	./bundle.sh release

check-swiftly:
	@command -v swiftly >/dev/null 2>&1 || { echo "Swiftly is required. Run brew install swiftly, then follow the toolchain setup in AGENTS.md." >&2; exit 1; }

# Development build and run
dev: check-swiftly
	swiftly run swift build -c debug
	@echo "Running in development mode..."
	./bundle.sh debug
	"./.build/Sparkdock Manager.app/Contents/MacOS/sparkdock-manager"

# Install through the same bundle and LaunchAgent steps as provisioning.
install:
	cd ../.. && ansible-playbook -i ansible/inventory.ini ansible/macos.yml --tags menubar -e ansible_become_pass= -e 'dev_env_dir=$(abspath ../..)'

# Unregister the LaunchAgent and remove the bundle and CLI link.
uninstall:
	launchctl bootout gui/$$(id -u) "$(HOME)/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist" 2>/dev/null || true
	rm -f "$(HOME)/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist" /opt/homebrew/bin/sparkdock-manager
	rm -rf "$(HOME)/Applications/Sparkdock Manager.app"

# Clean build artifacts
clean: check-swiftly
	swiftly run swift package clean
	rm -rf .build

# Test the application (build + unit tests)
test: build
	@echo "Running unit tests..."
	swiftly run swift test
	./test-bundle.sh
	@echo "Menu bar app built and tested successfully"
	@if test -x .build/release/sparkdock-manager; then \
		echo "✅ Executable created and is executable"; \
	else \
		echo "❌ Executable not found or not executable"; \
		exit 1; \
	fi
