// Package sysinfo gathers this machine's hardware summary (model, serial, chip,
// memory, disk) for the dashboard's system-info panel. It delegates to the same
// macOS tools sparkdock already uses (system_profiler, vm_stat, df, sysctl) via
// an injected command runner, so the parsing is unit-tested without invoking
// real binaries. Every field degrades to its zero value; Gather never errors.
package sysinfo

import (
	"context"
	"strconv"
	"strings"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
)

// Info is the gathered hardware summary. Sizes are in bytes.
type Info struct {
	Model     string
	Serial    string
	Chip      string
	Cores     int
	GPUCores  int
	MemTotal  uint64
	MemFree   uint64
	MemCached uint64
	DiskTotal uint64
	DiskFree  uint64
	OS        string
}

// Gatherer collects system info. Run is injected (reuse the same runner wired
// for status) so Gather is testable.
type Gatherer struct {
	Run status.CommandRunner
}

// Gather runs the underlying commands and assembles an Info. Intended to run in
// the background; system_profiler in particular is slow.
func (g Gatherer) Gather(ctx context.Context) Info {
	hw := parseHardware(g.Run(ctx, "system_profiler", "SPHardwareDataType", "SPDisplaysDataType").Stdout)

	if memsize := parseUint(g.Run(ctx, "sysctl", "-n", "hw.memsize").Stdout); memsize > 0 {
		hw.MemTotal = memsize
	}
	hw.MemFree, hw.MemCached = parseVMStat(g.Run(ctx, "vm_stat").Stdout)
	hw.DiskTotal, hw.DiskFree = parseDF(g.Run(ctx, "df", "-k", "/").Stdout)
	hw.OS = strings.TrimSpace(g.Run(ctx, "sw_vers", "-productVersion").Stdout)
	return hw
}

// parseHardware reads the combined SPHardwareDataType + SPDisplaysDataType text.
func parseHardware(out string) Info {
	var info Info
	var modelName, modelID string
	inDisplays := false
	for _, raw := range strings.Split(out, "\n") {
		line := strings.TrimSpace(raw)
		// SPDisplaysDataType output begins with the "Graphics/Displays:" header;
		// "Total Number of Cores" before it is the CPU, after it is the GPU.
		if strings.HasPrefix(line, "Graphics/Displays") {
			inDisplays = true
			continue
		}
		key, val, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		val = strings.TrimSpace(val)
		switch key {
		case "Model Name":
			modelName = val
		case "Model Identifier":
			modelID = val
		case "Chip":
			info.Chip = val
		case "Serial Number (system)":
			info.Serial = val
		case "Memory":
			info.MemTotal = parseMemoryGB(val)
		case "Total Number of Cores":
			if inDisplays {
				info.GPUCores = leadingInt(val)
			} else {
				info.Cores = leadingInt(val)
			}
		}
	}
	info.Model = modelName
	if modelID != "" {
		if modelName != "" {
			info.Model = modelName + " (" + modelID + ")"
		} else {
			info.Model = modelID
		}
	}
	return info
}

// parseVMStat returns (free, cached) memory in bytes from `vm_stat` output.
// free is immediately-available memory (free + speculative pages); cached is the
// reclaimable file cache (inactive + purgeable pages), shown the way Activity
// Monitor distinguishes free memory from "Cached Files".
func parseVMStat(out string) (free, cached uint64) {
	pageSize := uint64(4096)
	if i := strings.Index(out, "page size of "); i >= 0 {
		if n := leadingInt(out[i+len("page size of "):]); n > 0 {
			pageSize = uint64(n)
		}
	}
	var freePages, cachedPages uint64
	for _, raw := range strings.Split(out, "\n") {
		line := strings.TrimSpace(raw)
		key, val, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		n := uint64(leadingInt(strings.TrimSpace(val)))
		switch key {
		case "Pages free", "Pages speculative":
			freePages += n
		case "Pages inactive", "Pages purgeable":
			cachedPages += n
		}
	}
	return freePages * pageSize, cachedPages * pageSize
}

// parseDF returns (total, free) bytes for the root filesystem from `df -k /`.
// macOS columns: Filesystem 1024-blocks Used Available Capacity ...
func parseDF(out string) (total, free uint64) {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) < 2 {
		return 0, 0
	}
	f := strings.Fields(lines[1])
	if len(f) < 4 {
		return 0, 0
	}
	total = parseUint(f[1]) * 1024
	free = parseUint(f[3]) * 1024
	return total, free
}

// parseMemoryGB turns a "36 GB" string into bytes.
func parseMemoryGB(s string) uint64 {
	n := leadingInt(s)
	if n <= 0 {
		return 0
	}
	mult := uint64(1)
	switch {
	case strings.Contains(s, "TB"):
		mult = 1 << 40
	case strings.Contains(s, "GB"):
		mult = 1 << 30
	case strings.Contains(s, "MB"):
		mult = 1 << 20
	}
	return uint64(n) * mult
}

// leadingInt parses the leading integer of s (e.g. "12 (8 performance…)" -> 12).
func leadingInt(s string) int {
	s = strings.TrimSpace(s)
	end := 0
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	if end == 0 {
		return 0
	}
	n, _ := strconv.Atoi(s[:end])
	return n
}

func parseUint(s string) uint64 {
	n, _ := strconv.ParseUint(strings.TrimSpace(s), 10, 64)
	return n
}
