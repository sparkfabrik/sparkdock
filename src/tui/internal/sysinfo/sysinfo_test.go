package sysinfo

import (
	"context"
	"testing"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
)

const hardwareOut = `Hardware:

    Hardware Overview:

      Model Name: MacBook Pro
      Model Identifier: Mac15,6
      Chip: Apple M3 Pro
      Total Number of Cores: 12 (8 performance and 4 efficiency)
      Memory: 36 GB
      Serial Number (system): ABCD1234XYZ

Graphics/Displays:

      Chipset Model: Apple M3 Pro
      Type: GPU
      Total Number of Cores: 18
`

func TestParseHardware(t *testing.T) {
	got := parseHardware(hardwareOut)
	if got.Model != "MacBook Pro (Mac15,6)" {
		t.Errorf("Model = %q", got.Model)
	}
	if got.Chip != "Apple M3 Pro" {
		t.Errorf("Chip = %q", got.Chip)
	}
	if got.Serial != "ABCD1234XYZ" {
		t.Errorf("Serial = %q", got.Serial)
	}
	if got.Cores != 12 {
		t.Errorf("Cores = %d, want 12", got.Cores)
	}
	if got.GPUCores != 18 {
		t.Errorf("GPUCores = %d, want 18", got.GPUCores)
	}
	if got.MemTotal != 36<<30 {
		t.Errorf("MemTotal = %d, want %d", got.MemTotal, uint64(36)<<30)
	}
}

func TestParseVMStat(t *testing.T) {
	out := `Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                          1000.
Pages active:                        9000.
Pages inactive:                      2000.
Pages speculative:                    500.
Pages purgeable:                      300.
`
	free, cached := parseVMStat(out)
	// free + speculative
	if want := uint64(1500) * 16384; free != want {
		t.Errorf("free = %d, want %d", free, want)
	}
	// inactive + purgeable
	if want := uint64(2300) * 16384; cached != want {
		t.Errorf("cached = %d, want %d", cached, want)
	}
}

func TestParseDF(t *testing.T) {
	out := `Filesystem  1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s1s1 971350180 20000000 400000000    20%    /
`
	total, free := parseDF(out)
	if total != 971350180*1024 {
		t.Errorf("total = %d", total)
	}
	if free != 400000000*1024 {
		t.Errorf("free = %d", free)
	}
}

func TestParseMemoryGB(t *testing.T) {
	if got := parseMemoryGB("36 GB"); got != 36<<30 {
		t.Errorf("36 GB = %d", got)
	}
	if got := parseMemoryGB("1 TB"); got != 1<<40 {
		t.Errorf("1 TB = %d", got)
	}
	if got := parseMemoryGB("nonsense"); got != 0 {
		t.Errorf("nonsense = %d, want 0", got)
	}
}

func TestGather_UsesInjectedRunner(t *testing.T) {
	g := Gatherer{Run: func(_ context.Context, name string, args ...string) status.CommandResult {
		switch name {
		case "system_profiler":
			return status.CommandResult{Stdout: hardwareOut}
		case "sysctl":
			return status.CommandResult{Stdout: "38654705664\n"} // 36 GiB
		case "vm_stat":
			return status.CommandResult{Stdout: "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 1000.\nPages inactive: 500.\n"}
		case "df":
			return status.CommandResult{Stdout: "Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/disk3 100 40 60 40% /\n"}
		case "sw_vers":
			return status.CommandResult{Stdout: "26.1\n"}
		}
		return status.CommandResult{}
	}}
	got := g.Gather(context.Background())
	if got.Serial != "ABCD1234XYZ" || got.Chip != "Apple M3 Pro" {
		t.Errorf("hardware not parsed: %+v", got)
	}
	if got.MemTotal != 38654705664 {
		t.Errorf("MemTotal from sysctl = %d", got.MemTotal)
	}
	if got.MemFree != 1000*16384 {
		t.Errorf("MemFree = %d", got.MemFree)
	}
	if got.MemCached != 500*16384 {
		t.Errorf("MemCached = %d", got.MemCached)
	}
	if got.DiskFree != 60*1024 {
		t.Errorf("DiskFree = %d", got.DiskFree)
	}
	if got.OS != "26.1" {
		t.Errorf("OS = %q", got.OS)
	}
}
