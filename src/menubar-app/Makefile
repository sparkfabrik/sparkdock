# Makefile for Sparkdock Menu Bar App

.PHONY: build install uninstall clean test dev

# Build the application
build:
	swift build -c release

# Development build and run
dev:
	swift build -c debug
	@echo "Running in development mode..."
	./.build/debug/sparkdock-manager

# Install the application (requires sudo for /usr/local/bin)
install: build
	sudo cp .build/release/sparkdock-manager /usr/local/bin/
	sudo chmod 755 /usr/local/bin/sparkdock-manager
	cp com.sparkfabrik.sparkdock.menubar.plist ~/Library/LaunchAgents/
	/usr/local/bin/launchctl-helper reload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist

# Uninstall the application
uninstall:
	/usr/local/bin/launchctl-helper unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
	sudo rm -f /usr/local/bin/sparkdock-manager

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Test the application (build + unit tests)
test: build
	@echo "Running unit tests..."
	swift test
	@echo "Menu bar app built and tested successfully"
	@if test -x .build/release/sparkdock-manager; then \
		echo "✅ Executable created and is executable"; \
	else \
		echo "❌ Executable not found or not executable"; \
		exit 1; \
	fi