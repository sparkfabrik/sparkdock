# Default branch name (change to "main" when migrating)
DEFAULT_BRANCH := master

run-ansible-macos:
ifeq ($(TAGS),)
	@if ! timeout 300 ansible-playbook ./ansible/macos.yml --ask-become-pass; then \
		exit_code=$$?; \
		if [ $$exit_code -eq 124 ]; then \
			echo "❌ Ansible playbook timed out after 5 minutes. This usually happens when:"; \
			echo "   - Wrong sudo password was entered"; \
			echo "   - System is unresponsive during fact gathering"; \
			echo "💡 Please try again with the correct password."; \
		fi; \
		exit $$exit_code; \
	fi
else
	@if ! timeout 300 ansible-playbook ./ansible/macos.yml --ask-become-pass --tags=$(TAGS); then \
		exit_code=$$?; \
		if [ $$exit_code -eq 124 ]; then \
			echo "❌ Ansible playbook timed out after 5 minutes. This usually happens when:"; \
			echo "   - Wrong sudo password was entered"; \
			echo "   - System is unresponsive during fact gathering"; \
			echo "💡 Please try again with the correct password."; \
		fi; \
		exit $$exit_code; \
	fi
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
