# Makefile for Sparkdock Menu Bar App

.PHONY: build install uninstall clean test

# Build the application
build:
	swift build -c release

# Install the application (requires sudo for /usr/local/bin)
install: build
	sudo cp .build/release/sparkdock-manager /usr/local/bin/
	sudo chmod 755 /usr/local/bin/sparkdock-manager
	cp com.sparkfabrik.sparkdock.menubar.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist 2>/dev/null || true
	launchctl load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist

# Uninstall the application
uninstall:
	launchctl unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist 2>/dev/null || true
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
	@.build/release/sparkdock-manager --help 2>/dev/null || echo "App executable created"