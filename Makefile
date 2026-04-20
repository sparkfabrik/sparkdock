# Default branch name (change to "main" when migrating)
DEFAULT_BRANCH := master

run-ansible-playbook:
	@# Check if just binary is available, install if needed
	@if ! command -v just >/dev/null 2>&1; then \
		echo "Just not found. Installing just via Homebrew..."; \
		brew install just; \
	fi
	@# Delegate to the justfile implementation
ifeq ($(TAGS),)
	just run-ansible-playbook
else
	just run-ansible-playbook TAGS="$(TAGS)"
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
	printf '%s\n' \
		'#compdef sjust' \
		'' \
		'# Zsh completion for sjust — a just wrapper with a fixed justfile.' \
		'# Calls just directly with JUST_JUSTFILE scoped to the subprocess, filtering' \
		"# out just's own flags (--*) so that only recipes are completed." \
		'_sjust() {' \
		'  local _CLAP_COMPLETE_INDEX=$$(expr $$CURRENT - 1)' \
		"  local _CLAP_IFS=$$'\\n'" \
		'' \
		'  local completions=("$${(@f)$$(' \
		'    _CLAP_IFS="$$_CLAP_IFS" \' \
		'    _CLAP_COMPLETE_INDEX="$$_CLAP_COMPLETE_INDEX" \' \
		'    JUST_COMPLETE="zsh" \' \
		'    JUST_JUSTFILE="/opt/sparkdock/sjust/Justfile" \' \
		'    just -- "$${words[@]}" 2>/dev/null \' \
		"    | grep -v '^--'" \
		'  )}")' \
		'' \
		'  if [[ -n $$completions ]]; then' \
		'    local -a other=()' \
		'    local completion' \
		'    for completion in $$completions; do' \
		'      other+=("$$completion")' \
		'    done' \
		'    [[ -n $$other ]] && _describe '"'"'recipes'"'"' other' \
		'  fi' \
		'}' \
		'' \
		'_sjust "$$@"' \
	| sudo tee "$$BREW_PREFIX/share/zsh/site-functions/_sjust" > /dev/null; \
	sudo chown $$(id -u):$$(id -g) "$$BREW_PREFIX/share/zsh/site-functions/_sjust"; \
	sudo chmod 644 "$$BREW_PREFIX/share/zsh/site-functions/_sjust"
	@echo "✅ sjust installed successfully!"
	@echo "You can now run: sjust http-proxy-install-update"
