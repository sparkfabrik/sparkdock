// SparkFabrik fork of Herdr's workspace-chrome mod: the sidebar's brand row and footer
// in the SparkFabrik app kit (HERDR in the display face, bordered small buttons, LED icons,
// Settings and Add machine side by side).
//
// Sizes are logical: Herdr multiplies them by the person's zoom. They come from the
// app kit at 1x, scaled so its 15px text lands on Herdr's 11.8.
import { View, div, image, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, run, props, window, shared, setShared, updates, layout } from "herdr";

const u = (px) => (11.8 * px) / 15;
// An app kit icon: the lit dots over the unlit 7x7 grid at 13%, both in the text colour.
const icon = (name, size) => div().relative().flex_none().size(size)
  .child(svg("mods/sparkfabrik-chrome/icons/grid.svg").absolute().top(0).left(0).size(size).opacity(0.13))
  .child(svg(`mods/sparkfabrik-chrome/icons/${name}.svg`).absolute().top(0).left(0).size(size));
const fieldBorder = (t) => t.field_border ?? t.dim + "99";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// To the rail (on macOS wide enough for the traffic lights), or back to the width it had.
function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  // Mods edited before the rail went by width still read the flag.
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", { id: "sidebar", px: narrow() ? (shared("sidebar.width") ?? 268) : window()?.platform === "macos" ? 76 : 44 });
}

export default class WorkspaceChrome extends View {
  // app-btn--sm with an icon: 36px tall, 14px sides, 1px field border, radius 8.
  button(id, name, label, action) {
    const t = theme();
    return div().id(id).h(u(36)).px(u(14)).flex_none().flex().items_center().justify_center()
      .rounded(u(8)).border(1).border_color(fieldBorder(t)).bg(t.surface).text_color(t.foreground)
      .hover(s => s.bg(t.hover)).tooltip(label)
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action).child(icon(name, u(21)));
  }

  render() {
    const t = theme();
    const collapsed = narrow();
    if (props()?.footer) {
      // app-rail__link: 44px tall, 12px sides, radius 8, LED icon and 18px text in the second ink.
      // On the collapsed rail the two stack as 20px icon buttons, so both fit the footer's 44.
      const link = (id, name, label, action) => h_flex().id(id).flex_1().min_w(0).h(u(44)).px(u(12)).gap(u(8)).items_center().rounded(u(8))
        .when(collapsed, el => el.relative().flex_none().w(32).h(20).px(0).justify_center().rounded(u(6)).tooltip(label))
        .text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground)).cursor_pointer()
        .on_click(action).child(icon(name, collapsed ? u(16) : u(21)))
        .when(!collapsed, el => el.child(div().truncate().child(label)));
      const ready = div().size(6).rounded_full().bg(t.accent);
      return h_flex().size_full().bg(t.chrome).border_t(1).border_color(t.border).px(u(12)).gap(u(4)).items_center().text_size(u(18))
        .when(collapsed, el => el.flex_col().px(0).gap(2).justify_center())
        .child(link("settings", "settings", "Settings", () => run("app.settings"))
          .when(Boolean(updates().app.ready), el => el.child(collapsed ? ready.absolute().top(5).right(6) : ready)))
        .child(link("machine", "add", "Add machine", () => run("mod.open", { name: "machine-add" })));
    }
    return h_flex().size_full().bg(t.chrome).pl(collapsed ? 6 : u(24)).pr(u(16)).gap(u(4)).items_center()
      .when(window()?.platform === "macos" && !window()?.fullscreen && !collapsed, el => el.pl(76))
      .when(!collapsed, el => el.child(h_flex().flex_1().gap(u(10)).items_center()
        .child(image("frame/welcome/herdr.png").size(u(32)).rounded(u(6)))
        .child(div().font_family("Barlow Condensed").font_bold().italic().text_size(u(26)).text_color(t.foreground).child("HERDR"))))
      .when(!collapsed, el => el.child(this.button("search", "search", "Search", () => run("mod.open", { name: "picker" }))))
      // On the macOS rail the traffic lights fill the row; the agents list's » unfolds it.
      .when(!(collapsed && window()?.platform === "macos"), el => el.child(this.button("sidebar-toggle", collapsed ? "next" : "previous", collapsed ? "Expand the sidebar" : "Collapse the sidebar", toggleSidebar)));
  }
}
