#!/usr/bin/env zsh
# Sparkdock Shell Completions
# This file configures modern shell command completions for an enhanced, discoverable CLI experience

# Helper function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# AI tool completions
if command_exists opencode; then
  source <(opencode completion)
fi

if command_exists openspec; then
  source <(openspec completion generate zsh)
fi
