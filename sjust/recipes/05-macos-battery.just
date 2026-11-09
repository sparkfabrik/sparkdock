# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# 05-macos-battery.just lives at <sparkdock_root>/sjust/recipes/
_macos_battery_health_sh := clean(source_directory() / "../..") / "sjust/scripts/macos-battery-health.sh"

# Show battery health: cycle count, condition, maximum capacity, adapter and charging state.
[group('macos')]
macos-battery-health:
    @bash "{{_macos_battery_health_sh}}"
