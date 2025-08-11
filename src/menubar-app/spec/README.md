# Sparkdock Manager - AI Agent Specification

This directory contains comprehensive specifications for the Sparkdock Manager menu bar application, designed to help AI agents (like Claude Code) understand the system architecture, implementation details, and decision rationale.

## Directory Structure

```
spec/
├── README.md                    # This file - overview and navigation
├── system-architecture.md      # High-level system design and components
├── technical-specification.md  # Detailed technical implementation
├── ai-agent-context.md         # Context for AI agents working on this codebase
├── decision-records/           # Architecture Decision Records (ADRs)
├── api-integration.md          # External system integrations
├── user-workflows.md           # User interaction patterns and flows
└── troubleshooting.md          # Known issues and debugging guides
```

## Purpose

This specification follows 2025 AI agent documentation best practices to ensure:

1. **AI Agent Comprehension**: Clear context for LLMs to understand system purpose and architecture
2. **Decision Transparency**: Rationale behind technical choices for future development
3. **Integration Clarity**: How the system interacts with external components (Sparkdock, macOS)
4. **Maintenance Guidance**: Instructions for updates, debugging, and evolution

## Key System Overview

The Sparkdock Manager is a native macOS menu bar application that:
- Monitors Sparkdock system updates via Git repository checks
- Provides visual status indicators (white/orange icon states)
- Offers quick access to system management commands
- Integrates with Terminal.app for command execution
- Supports auto-startup via LaunchAgent or modern login items

## AI Agent Quick Start

For AI agents working on this codebase:

1. **Read First**: `system-architecture.md` for overall understanding
2. **Implementation Details**: `technical-specification.md` for code-level specifics
3. **Context**: `ai-agent-context.md` for AI-specific guidance
4. **Decisions**: Browse `decision-records/` for historical context

## Human Developer Notes

This specification structure is designed to maximize AI agent effectiveness when working on this codebase. Each document provides specific context that helps LLMs understand not just what the code does, but why it was implemented that way.

## Version

Specification Version: 1.0  
Last Updated: 2025-08-11  
Compatible with: Sparkdock Manager v1.0+