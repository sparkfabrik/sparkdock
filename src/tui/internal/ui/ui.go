// Package ui holds shared types for the TUI layer: page identifiers and the
// navigation messages pages emit. Keeping these in a leaf package lets both the
// app router and the individual pages depend on them without an import cycle.
package ui

// PageID identifies a top-level page.
type PageID int

const (
	PageSplash PageID = iota
	PageDashboard
	PageRunner
	PagePassword
	PageLog
	PageRecipes
	PageWhatsNew
)

// NavigateMsg asks the app router to switch pages. Action names the operation a
// page should perform on arrival (e.g. the run title for the Runner).
type NavigateMsg struct {
	To     PageID
	Action string
}

// Navigate is a convenience constructor returning a command-friendly message.
func Navigate(to PageID, action string) NavigateMsg {
	return NavigateMsg{To: to, Action: action}
}
