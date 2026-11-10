// SparkFabrik fork of Herdr's pane header mod, for layouts that frame their panes:
//   { "tab": "active", "pane": { "header": { "content": { "mod": "sparkfabrik-pane" } } } }
// The app kit's look: the program's icon, its name at title size, the folder in mono, and
// the state as the LED seed with its word; on hover, split, zoom and close as LED icons.
// Props from the app: { pane, terminal }. Click: focus the pane.
// Sizes are logical (Herdr multiplies them by the zoom), from the kit at 1x scaled to Herdr's text.

import { View, div, svg, image } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { panes, props, run, theme, home, layout } from "herdr";

const u = (px) => (11.8 * px) / 15;

// An app kit icon: the lit dots over the unlit 7x7 grid at 13%, both in the text colour.
const ledIcon = (name, size) => div().relative().flex_none().size(size)
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
const WORD = { working: "Working", blocked: "Needs you", done: "Done" };

// Match the first visible tab frame, including the active child of a stack.
function paneFrame(node) {
  if (!node || node.hidden) return null;
  if (node.content?.tab && node.content.pane) return node.content.pane;
  let children = node.children ?? [];
  if (node.type === "stack") {
    const visible = children.filter(child => !child.hidden);
    children = [visible.find(child => child.id === node.active) ?? visible[0]];
  }
  for (const child of children) {
    const frame = paneFrame(child);
    if (frame) return frame;
  }
  return null;
}

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
}

export default class Pane extends View {
  init() { this.hovered = false; }

  me() {
    return panes().find((p) => p.pane === props()?.pane);
  }

  button(t, id, name, command, args) {
    return div()
      .id(id)
      .p(u(4))
      .rounded(u(6))
      .text_color(t.muted)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        run(command, args);
      })
      .child(ledIcon(name, u(18)));
  }

  render(cx) {
    const t = theme();
    const p = this.me();
    if (!p) return div();
    const name = ((p.program?.agent || p.program?.shell) && p.program.name) || p.title || p.program?.name || "shell";
    const pic = icon(p.program, u(20), t.muted);
    const st = p.status;
    const pane = p.pane;
    const bottom = paneFrame(layout())?.header?.position === "bottom";
    return h_flex()
      .id(`pane-head-${pane}`)
      .size_full()
      .px(u(16))
      .gap(u(12))
      .items_center()
      .bg(t.surface)
      .when(bottom, el => el.border_t(1))
      .when(!bottom, el => el.border_b(1))
      .border_color(t.border)
      .text_size(u(15))
      .on_hover((hovered, cx) => { this.hovered = hovered; cx.notify(); })
      .on_click(() => run("pane.focus", { pane }))
      .when(Boolean(pic), (el) => el.child(pic))
      .child(div().flex_none().truncate().max_w(260).text_size(u(18)).font_semibold().text_color(t.foreground).child(name))
      .child(div().flex_1().truncate().font_family("Azeret Mono").text_color(t.muted).child(folder(p.cwd)))
      .when(Boolean(WORD[st]), el => el.child(h_flex().flex_none().gap(u(8)).items_center().font_semibold().text_color(t[st]).child(ledSeed(t, st)).child(WORD[st])))
      .when(this.hovered, el => el
        .child(this.button(t, `ph-r-${pane}`, "split-right", "pane.split", { direction: "right", pane }))
        .child(this.button(t, `ph-d-${pane}`, "split-down", "pane.split", { direction: "down", pane }))
        .child(this.button(t, `ph-z-${pane}`, p.zoomed ? "minus" : "expand", "pane.zoom", { pane }))
        .child(this.button(t, `ph-x-${pane}`, "close", "pane.close", { pane })));
  }
}
