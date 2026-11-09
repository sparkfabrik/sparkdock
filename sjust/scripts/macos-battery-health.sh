#!/usr/bin/env bash
set -euo pipefail

# sjust/scripts/macos-battery-health.sh: show macOS battery health (cycle
# count, condition, maximum capacity, adapter and charging state).
#
# Reads `system_profiler SPPowerDataType -json` for the condition and the
# reported maximum capacity, and `ioreg -arn AppleSmartBattery` for the raw
# controller capacities, lifetime temperatures and the model's rated cycle
# count (DesignCycleCount9C). The verdict compares against Apple's rating of
# 80% maximum capacity at that cycle count.
#
# Invoked by sjust/recipes/05-macos-battery.just.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../libs/libshell.sh
source "${SCRIPT_DIR}/../libs/libshell.sh"

RATED_CAPACITY=80

# Fields read from system_profiler and ioreg. Empty or unset means "not reported".
declare -A battery=()

# Print a line in bold when gum is available.
print_bold() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum style --bold "$1"
        return
    fi
    echo "$1"
}

# Flatten system_profiler and ioreg into key<TAB>value lines.
read_battery() {
    local key value

    while IFS=$'\t' read -r key value; do
        battery["${key}"]="${value}"
    done < <(python3 -I -c '
import json, plistlib, subprocess

def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return b""

profiler = run("/usr/sbin/system_profiler", "SPPowerDataType", "-json")
sections = {}
if profiler:
    sections = {s.get("_name"): s for s in json.loads(profiler).get("SPPowerDataType", [])}
info = sections.get("spbattery_information")
if not info:
    raise SystemExit(0)

health = info.get("sppower_battery_health_info", {})
charge = info.get("sppower_battery_charge_info", {})
charger = sections.get("sppower_ac_charger_information", {})

condition = health.get("sppower_battery_health", "")
# System Settings shows the "Good" state as "Normal".
if condition == "Good":
    condition = "Normal"

fields = {
    "present": "yes",
    "cycles": health.get("sppower_battery_cycle_count", ""),
    "condition": condition,
    "capacity": str(health.get("sppower_battery_health_maximum_capacity", "")).rstrip("%"),
    "adapter_connected": "yes" if charger.get("sppower_battery_charger_connected") == "TRUE" else "no",
    "adapter_watts": charger.get("sppower_ac_charger_watts", ""),
    "charging": "yes" if charge.get("sppower_battery_is_charging") == "TRUE" else "no",
}

raw = run("/usr/sbin/ioreg", "-arn", "AppleSmartBattery")
entries = plistlib.loads(raw) if raw else []
if entries:
    smart = entries[0]
    data = smart.get("BatteryData", {})
    lifetime = data.get("LifetimeData", {})
    fields["rated_cycles"] = smart.get("DesignCycleCount9C", "")
    fields["design_mah"] = smart.get("DesignCapacity", "")
    fields["raw_max_mah"] = smart.get("AppleRawMaxCapacity", "")
    fields["nominal_mah"] = smart.get("NominalChargeCapacity", "")
    fields["daily_max_soc"] = data.get("DailyMaxSoc", "")
    # LifetimeData reports the average in tenths of a degree and the maximum in degrees.
    average = lifetime.get("AverageTemperature")
    maximum = lifetime.get("MaximumTemperature")
    if average is not None:
        fields["temp_avg"] = "%.1f °C" % (average / 10)
    if maximum is not None:
        fields["temp_max"] = "%d °C" % maximum

for key, value in fields.items():
    print(f"{key}\t{value}")
')
}

lead_line() {
    local condition="${battery[condition]:-}"
    local capacity="${battery[capacity]:-}"
    local cycles="${battery[cycles]:-}"
    local summary=""

    if [[ -n "${capacity}" && -n "${cycles}" ]]; then
        summary="${capacity}% maximum capacity after ${cycles} cycles."
    elif [[ -n "${capacity}" ]]; then
        summary="${capacity}% maximum capacity."
    fi

    if [[ -z "${condition}" ]]; then
        echo "Battery has ${summary:-no capacity data reported.}"
        return
    fi

    local verdict="Battery needs attention."
    if [[ "${condition}" = Normal ]]; then
        verdict="Battery is healthy."
    fi
    if [[ -z "${summary}" ]]; then
        echo "${verdict} Condition is ${condition}."
        return
    fi
    echo "${verdict} Condition is ${condition}, with ${summary}"
}

# Compare against Apple's rating for this model only; no other thresholds.
rating_line() {
    local capacity="${battery[capacity]:-}"
    local cycles="${battery[cycles]:-}"
    local rated="${battery[rated_cycles]:-}"

    [[ -n "${capacity}" && -n "${cycles}" && -n "${rated}" ]] || return 0

    local rating="Apple's rating of ${RATED_CAPACITY}% maximum capacity at ${rated} cycles for this model"
    local prefix="${capacity}% at ${cycles} cycles"
    if (( cycles < rated && capacity >= RATED_CAPACITY )); then
        echo "${prefix} is within ${rating}."
    elif (( cycles < rated )); then
        echo "${prefix} is below ${rating}."
    elif (( capacity >= RATED_CAPACITY )); then
        echo "${prefix} exceeds ${rating}."
    else
        echo "${prefix} is past ${rating}."
    fi
}

condition_note() {
    [[ -n "${battery[condition]:-}" ]] || return 0
    echo "Condition is the signal to act on: macOS changes it from Normal to Service Recommended when the battery needs service."
}

charging_note() {
    [[ "${battery[adapter_connected]:-}" = yes && "${battery[charging]:-}" = no ]] || return 0
    echo "\"Charging: No\" while plugged in is normal: macOS pauses charging when the battery is full or Optimized Battery Charging holds it."
}

# "<mAh> mAh (<percent of design>%)", or nothing when the value is missing.
mah_of_design() {
    local mah="$1"
    local design="${battery[design_mah]:-0}"
    [[ -n "${mah}" ]] || return 0
    if (( design > 0 )); then
        echo "${mah} mAh ($(( (mah * 100 + design / 2) / design ))% of design)"
        return
    fi
    echo "${mah} mAh"
}

summary_table() {
    local adapter="not connected"
    if [[ "${battery[adapter_connected]:-}" = yes ]]; then
        adapter="connected"
        if [[ -n "${battery[adapter_watts]:-}" ]]; then
            adapter="${battery[adapter_watts]}W, connected"
        fi
    fi

    local charging="No"
    if [[ "${battery[charging]:-}" = yes ]]; then
        charging="Yes"
    fi

    local capacity="not reported"
    if [[ -n "${battery[capacity]:-}" ]]; then
        capacity="${battery[capacity]}%"
    fi

    {
        printf 'Field\tValue\n'
        printf 'Cycle Count\t%s\n' "${battery[cycles]:-not reported}"
        printf 'Condition\t%s\n' "${battery[condition]:-not reported}"
        printf 'Maximum Capacity\t%s\n' "${capacity}"
        printf 'Adapter\t%s\n' "${adapter}"
        printf 'Charging\t%s\n' "${charging}"
    } | render_table
}

# Raw controller data from ioreg. Rows whose key is absent are left out.
controller_table() {
    [[ -n "${battery[design_mah]:-}" ]] || return 0

    local row label value
    local -a rows=(
        "Design Capacity|${battery[design_mah]} mAh"
        "Raw Max Capacity|$(mah_of_design "${battery[raw_max_mah]:-}")"
        "Nominal Charge Capacity|$(mah_of_design "${battery[nominal_mah]:-}")"
        "Reported Maximum Capacity|${battery[capacity]:+${battery[capacity]}%}"
        "Average Temperature|${battery[temp_avg]:-}"
        "Maximum Temperature|${battery[temp_max]:-}"
        "Daily Max Charge|${battery[daily_max_soc]:+${battery[daily_max_soc]}%}"
    )

    echo
    print_bold "Battery controller data"
    echo
    {
        printf 'Field\tValue\n'
        for row in "${rows[@]}"; do
            label="${row%%|*}"
            value="${row#*|}"
            [[ -n "${value}" ]] || continue
            printf '%s\t%s\n' "${label}" "${value}"
        done
    } | render_table
    echo
    echo "macOS smooths the reported Maximum Capacity, so the raw controller figures are usually lower."
}

main() {
    if [[ "$(uname -s)" != Darwin ]]; then
        echo "macos-battery-health runs on macOS only." >&2
        exit 1
    fi

    read_battery
    if [[ "${battery[present]:-}" != yes ]]; then
        echo "No battery found: this Mac runs on mains power only."
        exit 0
    fi

    print_bold "$(lead_line)"
    echo
    summary_table
    echo

    local line
    for line in "$(rating_line)" "$(condition_note)" "$(charging_note)"; do
        if [[ -n "${line}" ]]; then
            echo "${line}"
        fi
    done

    controller_table
}

main "$@"
