# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/20-battery-health.just lives at <sparkdock_root>/sjust/recipes/shared/
_battery_health_sh := clean(source_directory() / "../../..") / "sjust/scripts/battery-health.sh"

# Show battery health: cycle count, condition, maximum capacity, adapter and charging state.
[group('system')]
battery-health:
    @bash "{{_battery_health_sh}}"
