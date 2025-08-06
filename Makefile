run-ansible-macos:
ifeq ($(TAGS),)
	ansible-playbook ./ansible/macos.yml --ask-become-pass
else
	ansible-playbook ./ansible/macos.yml --ask-become-pass --tags=$(TAGS)
endif

# Install sjust only (for manual http-proxy migration workflow)
install-sjust:
	@echo "Installing sjust executable and completion..."
	@# Check if we're on the latest master branch
	@if ! git diff --quiet HEAD origin/master 2>/dev/null; then \
		echo "❌ Error: Your sparkdock installation is not up to date with the latest master branch."; \
		echo ""; \
		echo "Please run the following commands to update first:"; \
		echo "  git fetch && git reset --hard origin/master"; \
		echo ""; \
		echo "Then run 'make install-sjust' again."; \
		exit 1; \
	fi
	@# Copy sjust executable
	sudo cp sjust/sjust.sh /usr/local/bin/sjust
	sudo chmod 755 /usr/local/bin/sjust
	@# Setup zsh completion
	@BREW_PREFIX=$$(brew --prefix 2>/dev/null || echo "/usr/local"); \
	mkdir -p "$$BREW_PREFIX/share/zsh/site-functions"; \
	just --completions zsh | sed -E 's/([\(_" ])just/\1sjust/g' > "$$BREW_PREFIX/share/zsh/site-functions/_sjust"; \
	chmod 644 "$$BREW_PREFIX/share/zsh/site-functions/_sjust"
	@echo "✅ sjust installed successfully!"
	@echo "You can now run: sjust install-http-proxy"
