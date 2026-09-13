# Makefile for Sparkdock Menu Bar App

.PHONY: build install uninstall clean test dev

# Build the application. The swiftbuild backend can fail before compiling on a
# machine with Command Line Tools only, so retry once with the native one.
build:
	@swift build -c release || { \
		echo "swift build failed; retrying with the native build system"; \
		swift build -c release --build-system native; \
	}

# Development build and run
dev:
	swift build -c debug
	@echo "Running in development mode..."
	./.build/debug/sparkdock-manager

# Install the application (user-owned /opt/homebrew/bin, no sudo)
install: build
	cp .build/release/sparkdock-manager /opt/homebrew/bin/
	chmod 755 /opt/homebrew/bin/sparkdock-manager
	cp com.sparkfabrik.sparkdock.menubar.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist 2>/dev/null || true
	launchctl load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist

# Uninstall the application
uninstall:
	launchctl unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
	rm -f /opt/homebrew/bin/sparkdock-manager

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