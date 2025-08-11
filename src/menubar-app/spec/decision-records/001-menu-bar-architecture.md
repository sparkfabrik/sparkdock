# ADR-001: Menu Bar Architecture Choice

## Status
Accepted

## Context
The original Sparkdock system used a launchd service with unreliable notification delivery. Users were often unaware when system updates were available, leading to outdated development environments.

## Decision
Implement a persistent macOS menu bar application instead of relying on notification-based updates.

## Rationale

### Why Menu Bar Application
1. **Always Visible**: Menu bar icons provide constant visual feedback
2. **Native UX**: Follows standard macOS application patterns
3. **Reliable**: No dependency on notification delivery mechanisms
4. **Quick Access**: One-click access to system management functions
5. **Status at a Glance**: Visual indicators (white/orange) immediately show system state

### Why Single-Class Design
- **Simplicity**: Menu bar apps are inherently simple; complex architectures add unnecessary overhead
- **Maintainability**: All logic in one place makes debugging and updates straightforward  
- **AI Agent Friendly**: Easier for future AI development assistance to understand and modify
- **Performance**: No abstraction layers or service communication overhead

### Why Swift Over Objective-C
- **Modern Language**: Better memory management and type safety
- **Concurrency**: Built-in async/await support for background operations
- **Package Manager**: Easier dependency management and build system
- **Maintainability**: More readable and less verbose than Objective-C

## Alternatives Considered

### 1. Enhanced Notification System
**Rejected**: macOS notification delivery is unreliable, especially for background processes

### 2. Web-Based Dashboard
**Rejected**: Requires browser interaction; doesn't provide at-a-glance status

### 3. Terminal-Based Status Command
**Rejected**: Requires manual checking; no persistent visual indicator

### 4. Complex Multi-Service Architecture
**Rejected**: Over-engineering for a simple status display application

## Consequences

### Positive
- Users always know system update status
- Native macOS integration and UX patterns
- Reliable operation independent of system notification settings
- Easy to extend with additional menu options
- Low resource usage (5-10MB memory)

### Negative  
- Requires GUI environment (doesn't work in headless/CI environments)
- Menu bar space usage (minimal impact)
- Slightly more complex than pure CLI approach

### Neutral
- Requires macOS 14+ (acceptable given Sparkdock's target environment)
- Uses modern Swift Package Manager build system

## Implementation Notes
- Background update checks every 4 hours balance freshness with performance
- Visual state changes (white/orange icon) provide immediate feedback
- Terminal integration preserves user's shell environment and aliases
- Graceful fallbacks ensure the app never appears broken (fallback icons, error handling)

## Future Considerations
- Could be extended to show other system metrics
- Menu structure allows for additional commands/tools
- Architecture supports future integration with other Sparkfabrik tools