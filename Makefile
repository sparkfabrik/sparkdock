# Default branch name (change to "main" when migrating)
DEFAULT_BRANCH := master

run-ansible-macos:
	@echo "Validating sudo access..."
	@if ! sudo -v; then \
		echo "❌ Failed to validate sudo access. Please check your password and try again."; \
		exit 1; \
	fi
ifeq ($(TAGS),)
	ansible-playbook ./ansible/macos.yml --ask-become-pass
else
	ansible-playbook ./ansible/macos.yml --ask-become-pass --tags=$(TAGS)
endif

# Install sjust only (for manual http-proxy migration workflow)
install-sjust:
	@echo "Installing sjust executable..."
	@# Check if we're on the latest $(DEFAULT_BRANCH) branch (skip in CI)
ifndef SKIP_GIT_CHECK
	@git fetch origin $(DEFAULT_BRANCH) 2>/dev/null || true
	@if ! git diff --quiet HEAD origin/$(DEFAULT_BRANCH) 2>/dev/null; then \
		echo "❌ Error: Your sparkdock installation is not up to date with the latest $(DEFAULT_BRANCH) branch."; \
		echo ""; \
		echo "Please run the following commands to update first:"; \
		echo "  git fetch && git reset --hard origin/$(DEFAULT_BRANCH)"; \
		echo ""; \
		echo "Then run 'make install-sjust' again."; \
		exit 1; \
	fi
else
	@echo "Skipping git check (SKIP_GIT_CHECK is set)"
endif
	@# Check if just binary is available, install if needed
	@if ! command -v just >/dev/null 2>&1; then \
		echo "Just not found. Installing just via Homebrew..."; \
		brew install just; \
	fi
	@# Copy sjust executable
	sudo cp sjust/sjust.sh /usr/local/bin/sjust
	sudo chmod 755 /usr/local/bin/sjust
	@# Generate zsh completion
	@echo "Generating zsh completion for sjust..."
	@BREW_PREFIX=$$(brew --prefix 2>/dev/null || echo "/usr/local"); \
	sudo mkdir -p "$$BREW_PREFIX/share/zsh/site-functions"; \
	just --completions zsh | sed -E 's/([\(_" ])just/\1sjust/g' | sudo tee "$$BREW_PREFIX/share/zsh/site-functions/_sjust" > /dev/null; \
	sudo chmod 644 "$$BREW_PREFIX/share/zsh/site-functions/_sjust"
	@echo "✅ sjust installed successfully!"
	@echo "You can now run: sjust http-proxy-install-update"
