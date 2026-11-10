// SparkFabrik fork of Herdr's workspace-status mod: the same bar, opened by the
// SparkFabrik harness mark (the spark of the SparkFabrik logo and its name), with
// the command palette key drawn as the design system's keycaps.
//
// Sizes are logical: Herdr multiplies them by the person's zoom, so they follow
// the panels' text. Ratios come from the SparkFabrik app kit (text 15, keycap 36,
// mark 18 tall, gaps 8 and 24, at 1x).
import { View, div, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, agents, theme, run, window, keys } from "herdr";

const TEXT = 11.8; // the bar's text, as Herdr's own status bar
const u = (px) => (TEXT * px) / 15; // a mockup px at the bar's text size

export default class WorkspaceStatus extends View {
  // The palette key as actually bound, split into keys; none when unbound.
  paletteKeys() {
    const mac = window()?.platform === "macos";
    const mod = { cmd: mac ? "⌘" : "Ctrl", ctrl: mac ? "⌃" : "Ctrl", shift: mac ? "⇧" : "Shift", alt: mac ? "⌥" : "Alt", option: mac ? "⌥" : "Alt" };
    const b = keys().find((k) => k.section === "global" && k.action === "app.palette");
    const parts = b && b.keys.endsWith("--") ? [...b.keys.slice(0, -2).split("-"), "-"] : b?.keys.split("-");
    return parts ? parts.map((p) => mod[p.toLowerCase()] ?? p.toUpperCase()) : [];
  }

  // The app kit's keycap (app-key) at a compact size for the bar: 28 instead of 36, mono 13,
  // 1px border with a 2px bottom edge.
  keycap(t, label) {
    return div().flex_none().min_w(u(28)).h(u(28)).px(u(6)).flex().items_center().justify_center()
      .rounded(u(5)).border(1).border_b(2).border_color(t.field_border ?? t.dim + "99").bg(t.surface)
      .font_family("Azeret Mono").text_size(u(13)).text_color(t.foreground)
      .child(label);
  }

  render() {
    const t = theme();
    const space = spaces().find(s => s.active);
    const list = agents();
    const needs = list.filter(a => a.status === "blocked").length;
    const harness = h_flex().gap(u(8)).items_center().text_color(t.foreground).font_semibold()
      .child(image("mods/sparkfabrik-status/spark-mark.svg").w(u(29)).h(u(18)).flex_none())
      .child("SparkFabrik harness");
    const palette = h_flex().id("palette").gap(u(4)).items_center().on_click(() => run("app.palette"))
      .children(this.paletteKeys().map((k) => this.keycap(t, k)))
      .child(div().ml(u(6)).child("Commands"));
    return h_flex().size_full().px(u(16)).gap(u(24)).items_center().bg(t.chrome).border_t(1).border_color(t.border).text_size(TEXT).text_color(t.muted)
      .child(harness)
      .child(div().child(space?.machine ?? "This computer"))
      .when(Boolean(space?.branch), el => el.child(div().child(space.branch)))
      .child(div().child(needs > 0 ? `${list.length} agents, ${needs} needs you` : `${list.length} agents`))
      .child(div().flex_1())
      .child(palette);
  }
}
