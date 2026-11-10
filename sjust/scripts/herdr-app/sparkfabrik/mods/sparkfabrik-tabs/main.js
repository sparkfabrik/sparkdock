// SparkFabrik fork of Herdr's tabs mod: app kit tabs (text tabs, the current one underlined in the
// ink), the program icon and the LED seed of its state, bordered small buttons with LED icons.
// Sizes are logical (Herdr multiplies them by the zoom), from the kit at 1x scaled to Herdr's text.
import { View, div, svg, image } from "gpui-kit";
// A namespace import, so a Herdr without ScrollHandle (before 0.1.15) still loads this mod.
import * as base from "gpui-base";
import { spaces, panes, run, openOverlay, theme, window, shared, layout, settings } from "herdr";

const { h_flex, v_flex } = base;
// Herdr 0.1.15 lets mods keep the active tab in view; older releases simply do
// not scroll it into view, and every other part of the tab bar works the same.
const ScrollHandle = base.ScrollHandle;
const u = (px) => (11.8 * px) / 15;
const fieldBorder = (t) => t.field_border ?? t.dim + "99";
// An app kit icon: the lit dots over the unlit 7x7 grid at 13%, both in the text colour.
const icon = (name, size) => div().relative().flex_none().size(size)
  .child(svg("mods/sparkfabrik-chrome/icons/grid.svg").absolute().top(0).left(0).size(size).opacity(0.13))
  .child(svg(`mods/sparkfabrik-chrome/icons/${name}.svg`).absolute().top(0).left(0).size(size));
// The LED seed (3 by 3) in the state's colour; working pulses, the rest stay still.
const SEED_LIT = { done: [1, 3, 4, 5, 7], blocked: [0, 2, 4, 6, 8], working: [0, 1, 2, 3], idle: [4] };
function ledSeed(t, status) {
  const color = t[status] ?? t.dim;
  const lit = SEED_LIT[status] ?? SEED_LIT.idle;
  const dot = (i) => {
    const on = lit.includes(i);
    const d = div().size(4).flex_none().rounded(2).bg(color).opacity(on ? 1 : 0.25);
    return on && status === "working" ? d.loop("opacity", { from: 0.35, to: 1, period: 1100 }) : d;
  };
  const row = (r) => h_flex().gap(2).child(dot(r * 3)).child(dot(r * 3 + 1)).child(dot(r * 3 + 2));
  return v_flex().flex_none().gap(2).child(row(0)).child(row(1)).child(row(2));
}

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

export default class Tabs extends View {
  init() {
    this.pressed = null;
    this.scroll = ScrollHandle ? ScrollHandle.new() : null;
    this.panels = JSON.parse(localStorage.getItem("panels") ?? "{}");
  }

  // Scroll a tab into view, where Herdr supports it.
  reveal(index) {
    if (this.scroll) this.scroll.scroll_to_item(index);
  }

  // The side panel is remembered per space: switching shows that space's choice
  // (closed if it never had one), and opening or closing it records it.
  syncPanel(space, panel, body, enabled) {
    if (!space || !panel) return;
    const now = panel.hidden ? null : body?.active ?? null;
    if (space.id !== this.space) {
      const first = this.space === undefined;
      this.space = space.id; this.pending = null;
      if (!(first && !(space.id in this.panels))) {
        const stored = this.panels[space.id] ?? null, want = enabled.includes(stored) ? stored : null;
        if (want !== now) {
          this.pending = { want, until: Date.now() + 1000 };
          if (want) { run("layout.select", { stack: "panel-body", child: want }); run("layout.show", { id: "panel" }); }
          else run("layout.hide", { id: "panel" });
          return;
        }
      }
    }
    // Until the restore lands (or something else won), the old state isn't a choice.
    if (this.pending) {
      if (this.pending.want !== now && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (this.panels[space.id] === now) return;
    this.panels[space.id] = now;
    localStorage.setItem("panels", JSON.stringify(this.panels));
  }

  render() {
    const t = theme();
    const space = spaces().find(p => p.active);
    const shown = space?.tabs ?? [];
    const active = shown.findIndex(tab => tab.active);
    const selected = shown[active]?.id;
    if (selected !== this.selected || active !== this.selectedIndex) {
      this.selected = selected;
      this.selectedIndex = active;
      if (active >= 0) this.reveal(active);
    }
    const stop = (_e, cx) => cx.stop_propagation();
    const button = (id, label, action) => div().id(id).h(u(36)).px(u(14)).flex_none().flex().items_center().justify_center()
      .rounded(u(8)).border(1).border_color(fieldBorder(t)).bg(t.surface).text_color(t.foreground).hover(s => s.bg(t.hover))
      .on_mouse_down("left", stop).on_click(action).child(label);
    const item = (c, i) => {
      const program = panes().find(p => p.tab === c.id && p.program?.agent)?.program ?? panes().find(p => p.tab === c.id)?.program;
      const name = /^tb\d+$/.test(c.name) ? program?.name ?? "Terminal" : c.name;
      return h_flex().id(`tab-${c.id}`).h_full().px(u(14)).gap(u(10)).items_center().flex_none().text_size(u(18))
        // A rename or status dot on this or an earlier tab can push the active one out.
        .when(Boolean(this.scroll) && i <= active, el => el.on_size_change((_size, cx) => { this.reveal(active); cx.notify(); }))
        .border_b(c.active ? 2 : 0).border_color(t.foreground).text_color(c.active ? t.foreground : t.muted)
        .when(c.active, el => el.font_semibold()).when(!c.active, el => el.font_medium())
        .hover(s => s.text_color(t.foreground))
        .on_mouse_down("left", (e, cx) => { cx.stop_propagation(); this.pressed = i; if (e.click_count === 2) run("tab.rename", { id: c.id }); })
        .on_mouse_up("left", () => {
          const from = this.pressed; this.pressed = null;
          if (from !== null && from !== i) run("tab.move", { id: shown[from].id, index: space.tabs.findIndex(x => x.id === c.id) + 1 });
          else run("tab.select", { id: c.id });
        })
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "menu", kind: "popup", width: 200, props: { tab: "tab", target: { id: c.id, space: space.id } } }); })
        .when(Boolean(program?.icon), el => el.child(program.tint ? svg(program.icon).size(u(20)).text_color(t.muted) : image(program.icon).size(u(20))))
        .child(div().max_w(170).truncate().child(c.zoomed ? `${name} Z` : name))
        .when(c.status === "working" || c.status === "blocked" || c.status === "done", el => el.child(ledSeed(t, c.status)))
        .when(c.active, el => el.child(div().id(`close-${c.id}`).text_color(t.dim).hover(s => s.text_color(t.foreground)).on_mouse_down("left", stop).on_click((_e, cx) => { cx.stop_propagation(); run("tab.close", { id: c.id }); }).child(icon("close", u(16)))));
    };
    const root = layout(), sidebar = find(root, "sidebar"), w = window();
    // Old saved rails and a dragged-narrow sidebar can be smaller than the window buttons.
    const lightsPadding = w?.platform === "macos" && w.titlebar === "none" && !w.fullscreen && root?.traffic_lights
      ? Math.max(10, (root.traffic_lights[0] + 64) / settings().zoom - (sidebar?.hidden ? 0 : sidebar?.size?.px ?? 0))
      : 10;
    const panel = find(root, "panel"), body = find(root, "panel-body");
    const enabled = shared("workspace.panels") ?? ["files", "changes"];
    this.syncPanel(space, panel, body, enabled);
    const panelButton = (id, label) => {
      const on = panel && !panel.hidden && body?.active === id;
      return h_flex().id(`panel-${id}`).h(u(36)).px(u(14)).flex_none().items_center().justify_center().rounded(u(8))
        .border(1).border_color(fieldBorder(t)).text_size(u(15)).font_semibold().bg(on ? t.raised : t.surface).text_color(t.foreground)
        .hover(s => s.bg(t.hover)).on_mouse_down("left", stop)
        .on_click(() => {
          if (on) run("layout.hide", { id: "panel" });
          else { run("layout.select", { stack: "panel-body", child: id }); run("layout.show", { id: "panel" }); }
        }).child(label);
    };
    return h_flex().size_full().min_w(0).px(u(16)).pl(lightsPadding).gap(u(8)).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .on_mouse_up("left", () => { this.pressed = null; })
      .on_scroll_wheel(e => { if (Math.abs(e.delta.y) >= 1) run(e.delta.y > 0 ? "tab.prev" : "tab.next"); })
      .child(h_flex().id("tab-scroll").flex_1().min_w(0).h_full().items_center().gap(3).overflow_x_scrollbar().gap(u(4))
        .when(Boolean(this.scroll), el => el.track_scroll(this.scroll)
          .on_size_change((_size, cx) => { if (active >= 0) { this.reveal(active); cx.notify(); } }))
        .children(shown.map(item)))
      .child(button("tab-new", icon("add", u(21)), () => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 })))
      .when(enabled.includes("files"), el => el.child(panelButton("files", "Files")))
      .when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes")))
      .when(w?.buttons, el => el.child(button("minimize", w.platform === "windows" ? svg("mods/sparkfabrik-tabs/win-min.svg").size(16) : "−", () => run("window.minimize")))
        .child(button("maximize", w.platform === "windows" ? svg(`mods/sparkfabrik-tabs/${w.maximized ? "win-restore" : "win-max"}.svg`).size(16) : "□", () => run("window.maximize")))
        .child(button("close-window", w.platform === "windows" ? svg("mods/sparkfabrik-tabs/win-close.svg").size(16) : svg("mods/sparkfabrik-chrome/herdr-icons/close.svg").size(13), () => run("window.close"))));
  }
}
