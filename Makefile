# Default branch name (change to "main" when migrating)
DEFAULT_BRANCH := master

run-ansible-macos:
ifeq ($(TAGS),)
	ansible-playbook ./ansible/macos.yml --ask-become-pass
else
	ansible-playbook ./ansible/macos.yml --ask-become-pass --tags=$(TAGS)
endif

# Install sjust only (for manual http-proxy migration workflow)
install-sjust:
	@echo "Installing sjust executable..."
	@# Check if we're on the latest master branch
	@if ! git diff --quiet HEAD origin/$(DEFAULT_BRANCH) 2>/dev/null; then \
		echo "❌ Error: Your sparkdock installation is not up to date with the latest $(DEFAULT_BRANCH) branch."; \
		echo ""; \
		echo "Please run the following commands to update first:"; \
		echo "  git fetch && git reset --hard origin/$(DEFAULT_BRANCH)"; \
		echo ""; \
		echo "Then run 'make install-sjust' again."; \
		exit 1; \
	fi
	@# Check if just binary is available, install if needed
	@if ! command -v just >/dev/null 2>&1; then \
		echo "Just not found. Installing just via Homebrew..."; \
		brew install just; \
	fi
	@# Copy sjust executable
	sudo cp sjust/sjust.sh /usr/local/bin/sjust
	sudo chmod 755 /usr/local/bin/sjust
	@echo "✅ sjust installed successfully!"
	@echo "You can now run: sjust install-http-proxy"
