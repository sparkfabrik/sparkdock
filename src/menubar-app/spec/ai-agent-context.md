# AI Agent Context - Sparkdock Manager

## Purpose for AI Agents

This document provides specific guidance for AI agents (like Claude Code) working on the Sparkdock Manager codebase. It explains not just what the code does, but the context and reasoning behind implementation decisions.

## System Context

### What Sparkdock Manager Solves

**Problem**: The original Sparkdock system used a fragile launchd notification system that frequently failed, leaving users unaware of available system updates.

**Solution**: A persistent menu bar application that provides:
- Always-visible status indicator
- Reliable update detection  
- Quick access to system commands
- Professional user experience

### Why This Architecture

**Single-Class Design**: Deliberately chose simplicity over complex service abstractions
- **Reasoning**: Menu bar apps are inherently simple; over-engineering adds complexity without benefit
- **Maintainability**: Easier for future developers/AI agents to understand and modify
- **Debugging**: All logic in one place makes troubleshooting straightforward

## Key Implementation Patterns

### 1. Configuration Constants Structure

```swift
private struct AppConstants {
    static let updateInterval: TimeInterval = 4 * 60 * 60
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
    // ...
}
```

**AI Agent Note**: All magic numbers and hardcoded paths are centralized here. When making changes:
- Always use constants instead of hardcoding values
- Update constants rather than scattered literals
- Consider backward compatibility when changing paths

### 2. Graceful Fallback Pattern

**Logo Loading Example**:
```swift
// 1. Try custom logo from bundle
// 2. Fall back to system symbol (macOS 11+)  
// 3. Fall back to generated shape
```

**AI Agent Guidance**: This pattern prevents UI failures. When modifying:
- Always provide fallbacks for external dependencies
- Test fallback paths explicitly
- Document fallback behavior for users

### 3. Background Processing Pattern

```swift
DispatchQueue.global(qos: .background).async { [weak self] in
    let result = self?.performCheck() ?? false
    DispatchQueue.main.async {
        self?.updateUI(result)
    }
}
```

**AI Agent Note**: Critical pattern for macOS apps:
- Never block main thread with long operations
- Always update UI on main thread
- Use `[weak self]` to prevent retain cycles

## Common Modification Scenarios

### Adding New Menu Items

1. **Update `setupMenu()` method**: Add menu item creation
2. **Add `@objc` action method**: Handle user interaction
3. **Update tags if needed**: For programmatic item access
4. **Test menu behavior**: Ensure proper enabling/disabling

### Changing Update Logic

1. **Modify `runSparkdockCheck()`**: Core update detection
2. **Update `updateUI()` method**: Reflect new states
3. **Consider `AppConstants`**: May need new configuration values
4. **Test edge cases**: Network failures, command unavailability

### Icon/Visual Changes

1. **Update `loadIcon()` method**: Main icon logic
2. **Modify `createDefaultIcon()`**: Fallback behavior
3. **Test on multiple macOS versions**: Symbol availability varies
4. **Consider accessibility**: Template icons vs. colored icons

## Integration Points for AI Agents

### 1. Sparkdock CLI Integration

**Location**: `runSparkdockCheck()` method  
**Command**: `/opt/sparkdock/bin/sparkdock.macos check-updates`  
**Exit Codes**:
- `0`: Updates available
- `1`: No updates available
- Other: Error condition

**AI Agent Note**: When modifying this integration:
- Understand that exit code logic is intentionally inverted from typical CLI tools
- The Sparkdock CLI handles all Git operations
- Never bypass this interface to access Git directly

### 2. Terminal Integration

**Location**: `executeTerminalCommand()` method  
**Method**: AppleScript execution  
**Purpose**: Launch commands in user's Terminal environment

**AI Agent Note**: This preserves user's Terminal setup (shell, aliases, environment). Don't replace with direct Process execution unless specifically required.

### 3. macOS System Integration

**Login Items**: Modern ServiceManagement (macOS 13+) vs. LaunchAgent (older)  
**Menu Bar**: Standard NSStatusItem with NSMenu  
**Notifications**: UserNotifications framework for system alerts

## Code Quality Guidelines for AI Agents

### 1. Maintain Simplicity

**Good**:
```swift
private func checkForUpdates() {
    // Simple, direct implementation
}
```

**Avoid**:
```swift
private protocol UpdateServiceProtocol { ... }
private class UpdateService: UpdateServiceProtocol { ... }
// Over-engineered for this use case
```

### 2. Handle Edge Cases

Always consider:
- **Network unavailability**: Git fetch failures
- **File system issues**: Missing executables, permissions
- **macOS version differences**: API availability
- **Resource loading failures**: Missing icons, bundles

### 3. Modern Swift Patterns

**Use**: Modern NSImage drawing API  
**Avoid**: Deprecated `lockFocus()`/`unlockFocus()`

**Use**: Proper error handling with logging  
**Avoid**: Silent failures without user feedback

### 4. Performance Awareness

- **Timer intervals**: 4-hour checks balance freshness with resource usage
- **Background queues**: Keep UI responsive during operations
- **Memory management**: Use `[weak self]` in closures appropriately

## Testing Considerations for AI Agents

### Unit Testing Strategy

Current tests focus on:
1. **Package structure validation**
2. **Resource existence verification**  
3. **Path construction correctness**
4. **Build system validation**

**When adding features**: Extend tests to cover new functionality without requiring GUI interaction.

### Manual Testing Checklist

1. **Icon states**: Verify white/orange transitions
2. **Menu behavior**: Check all menu items function correctly  
3. **Update detection**: Test with actual Git repository changes
4. **Fallback behavior**: Remove logo file and verify fallback icons
5. **Auto-startup**: Test LaunchAgent installation and loading

## Debugging Tips for AI Agents

### Common Issues

1. **Menu bar icon not appearing**: Check icon loading fallbacks
2. **Update checks failing**: Verify Sparkdock CLI path and permissions
3. **Menu items disabled**: Check update state management logic
4. **Auto-startup not working**: Verify LaunchAgent plist syntax

### Logging and Diagnostics

The app includes minimal logging to avoid noise. When debugging:
- Use Xcode debugger for interactive investigation
- Check Console.app for system-level errors
- Verify file permissions and paths manually

## Evolution Guidelines

### When to Refactor

**Consider refactoring when**:
- Adding 3+ new major features
- Supporting multiple update sources
- Adding complex state management

**Maintain current architecture for**:
- Simple feature additions
- Bug fixes
- Performance improvements
- UI/UX enhancements

### Backward Compatibility

- **macOS versions**: Support back to macOS 14 (current requirement)
- **Sparkdock integration**: Maintain CLI interface compatibility
- **LaunchAgent format**: Keep plist structure stable for existing installations

This context should help AI agents understand not just the current implementation, but the reasoning behind it and how to maintain consistency with the project's goals and constraints.