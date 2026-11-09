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

# Print one line in a style: "heading" (bold purple), "faint", or a 256-color
# foreground number. Plain text when gum is not available.
styled() {
    local style="$1" text="$2"
    if [[ "${HAS_GUM}" != true ]]; then
        echo "${text}"
        return
    fi
    case "${style}" in
        heading) gum style --bold --foreground 99 "${text}" ;;
        faint) gum style --faint "${text}" ;;
        *) gum style --foreground "${style}" "${text}" ;;
    esac
}

# Render label<TAB>value lines from stdin as an aligned key/value box, with
# grey labels and no header row. Falls back to column(1) without gum.
render_box() {
    local -a labels=() values=()
    local label value width=0 i body=""

    while IFS=$'\t' read -r label value; do
        labels+=("${label}")
        values+=("${value}")
        if (( ${#label} > width )); then
            width=${#label}
        fi
    done

    if [[ "${HAS_GUM}" != true ]]; then
        for i in "${!labels[@]}"; do
            printf '  %-*s  %s\n' "${width}" "${labels[i]}" "${values[i]}"
        done
        return
    fi

    # The labels are styled inside $(...), where gum sees no terminal and drops
    # color; force it only when this script itself writes to a terminal.
    local force_color=0
    if [[ -t 1 ]]; then
        force_color=1
    fi
    for i in "${!labels[@]}"; do
        if (( i > 0 )); then
            body+=$'\n'
        fi
        body+="$(CLICOLOR_FORCE="${force_color}" gum style --foreground 245 "${labels[i]}")"
        body+="$(printf '%*s' $(( width - ${#labels[i]} + 2 )) '')${values[i]}"
    done
    gum style --border rounded --border-foreground 240 --padding "0 1" "${body}"
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

def fail(message):
    print("error\t" + message)
    raise SystemExit(0)

profiler = run("/usr/sbin/system_profiler", "SPPowerDataType", "-json")
if not profiler:
    fail("system_profiler returned no power data.")
try:
    sections = {s.get("_name"): s for s in json.loads(profiler).get("SPPowerDataType", [])}
except (ValueError, AttributeError):
    fail("system_profiler returned power data that could not be read.")
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
try:
    entries = plistlib.loads(raw) if raw else []
except Exception:
    entries = []
if entries:
    smart = entries[0]
    # The controller knows the power state too: use it when system_profiler has no charger section.
    if not charger:
        fields["adapter_connected"] = "yes" if smart.get("ExternalConnected") else "no"
        fields["charging"] = "yes" if smart.get("IsCharging") else "no"
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

# Percentage of design capacity for a mAh value, or nothing when unknown.
percent_of_design() {
    local mah="$1"
    local design="${battery[design_mah]:-0}"
    if [[ -z "${mah}" ]] || (( design <= 0 )); then
        return 0
    fi
    echo "$(( (mah * 100 + design / 2) / design ))"
}

# "<mAh> mAh (<n>% of design)", or nothing when the value is missing.
mah_of_design() {
    local mah="$1" percent
    [[ -n "${mah}" ]] || return 0
    percent="$(percent_of_design "${mah}")"
    if [[ -n "${percent}" ]]; then
        echo "${mah} mAh (${percent}% of design)"
        return
    fi
    echo "${mah} mAh"
}

# One colored status line: green when healthy, yellow when capacity is below
# the rating, red when macOS reports any condition other than Normal.
status_line() {
    local condition="${battery[condition]:-}"
    local capacity="${battery[capacity]:-}"

    if [[ -z "${condition}" ]]; then
        styled 214 "● Condition not reported"
        return
    fi
    if [[ "${condition}" != Normal ]]; then
        styled 196 "● ${condition}: have the battery checked"
        return
    fi
    if [[ -n "${capacity}" ]] && (( capacity < RATED_CAPACITY )); then
        styled 214 "● Condition Normal, capacity below the ${RATED_CAPACITY}% rating"
        return
    fi
    styled 42 "● Healthy: condition Normal"
}

summary_rows() {
    local capacity="${battery[capacity]:-}"
    local cycles="${battery[cycles]:-}"
    local rated="${battery[rated_cycles]:-}"

    if [[ -n "${capacity}" && -n "${rated}" ]]; then
        printf 'Maximum capacity\t%s%% (Apple rates %s%% at %s cycles)\n' "${capacity}" "${RATED_CAPACITY}" "${rated}"
    elif [[ -n "${capacity}" ]]; then
        printf 'Maximum capacity\t%s%%\n' "${capacity}"
    fi

    if [[ -n "${cycles}" && -n "${rated}" ]]; then
        printf 'Cycle count\t%s of %s\n' "${cycles}" "${rated}"
    elif [[ -n "${cycles}" ]]; then
        printf 'Cycle count\t%s\n' "${cycles}"
    fi

    if [[ "${battery[adapter_connected]:-}" != yes ]]; then
        printf 'Power\tOn battery\n'
        return
    fi
    local adapter="Adapter connected"
    if [[ -n "${battery[adapter_watts]:-}" ]]; then
        adapter="${battery[adapter_watts]}W adapter"
    fi
    local state="not charging"
    if [[ "${battery[charging]:-}" = yes ]]; then
        state="charging"
    fi
    printf 'Power\t%s, %s\n' "${adapter}" "${state}"
}

controller_rows() {
    local avg="${battery[temp_avg]:-}" max="${battery[temp_max]:-}" temperature=""

    if [[ -n "${battery[design_mah]:-}" ]]; then
        printf 'Design capacity\t%s mAh\n' "${battery[design_mah]}"
    fi
    if [[ -n "${battery[raw_max_mah]:-}" ]]; then
        printf 'Raw max capacity\t%s\n' "$(mah_of_design "${battery[raw_max_mah]}")"
    fi
    if [[ -n "${battery[nominal_mah]:-}" ]]; then
        printf 'Nominal capacity\t%s\n' "$(mah_of_design "${battery[nominal_mah]}")"
    fi

    if [[ -n "${avg}" && -n "${max}" ]]; then
        temperature="${avg} average, ${max} max"
    elif [[ -n "${avg}" ]]; then
        temperature="${avg} average"
    elif [[ -n "${max}" ]]; then
        temperature="${max} max"
    fi
    if [[ -n "${temperature}" ]]; then
        printf 'Temperature\t%s\n' "${temperature}"
    fi

    if [[ -n "${battery[daily_max_soc]:-}" ]]; then
        printf 'Daily max charge\t%s%%\n' "${battery[daily_max_soc]}"
    fi
}

# Short notes, each printed only when its state applies.
notes() {
    local capacity="${battery[capacity]:-}"
    local raw line
    local -a lines=()
    raw="$(percent_of_design "${battery[raw_max_mah]:-}")"

    if [[ -n "${raw}" && -n "${capacity}" ]] && (( raw < capacity )); then
        lines+=("Raw figures are lower than the reported ${capacity}% because macOS smooths it.")
    fi
    if [[ "${battery[adapter_connected]:-}" = yes && "${battery[charging]:-}" = no ]]; then
        lines+=("Not charging while plugged in is normal when the battery is full or charging is optimized.")
    fi

    (( ${#lines[@]} > 0 )) || return 0
    # Without gum there is no box border to separate the notes from the rows.
    if [[ "${HAS_GUM}" != true ]]; then
        echo
    fi
    for line in "${lines[@]}"; do
        styled faint "${line}"
    done
}

main() {
    if [[ "$(uname -s)" != Darwin ]]; then
        echo "macos-battery-health runs on macOS only." >&2
        exit 1
    fi

    read_battery
    if [[ -n "${battery[error]:-}" ]]; then
        echo "Cannot read the battery state: ${battery[error]}" >&2
        exit 1
    fi
    if [[ "${battery[present]:-}" != yes ]]; then
        echo "No battery: this Mac runs on mains power only."
        exit 0
    fi

    styled heading "Battery health"
    status_line
    echo
    summary_rows | render_box

    local controller
    controller="$(controller_rows)"
    if [[ -n "${controller}" ]]; then
        echo
        styled heading "Controller"
        printf '%s\n' "${controller}" | render_box
    fi

    notes
}

main "$@"
