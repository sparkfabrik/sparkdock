import { execFileSync } from "node:child_process";
import { writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";

let cachedHasGum;

export function hasGum() {
  if (cachedHasGum !== undefined) {
    return cachedHasGum;
  }

  try {
    execFileSync("gum", ["--version"], { stdio: "ignore" });
    cachedHasGum = true;
  } catch {
    cachedHasGum = false;
  }

  return cachedHasGum;
}

export function printPlainTable(csv) {
  const rows = csv.split("\n").map((row) => row.split("\t"));
  const columns = rows[0].length;
  const widths = Array.from({ length: columns }, (_, index) =>
    Math.max(...rows.map((row) => (row[index] || "").length)),
  );
  const padCell = (value, width, index) =>
    index === 0
      ? (value || "").padEnd(width)
      : (value || "").padStart(width);
  const separator = widths.map((width) => "─".repeat(width)).join("──");
  const formatRow = (row) =>
    row.map((value, index) => padCell(value, widths[index], index)).join("  ");

  console.log(formatRow(rows[0]));
  console.log(separator);
  for (const row of rows.slice(1)) {
    console.log(formatRow(row));
  }
}

function printGumTable(csv) {
  const tmp = path.join(tmpdir(), `gum-table-${randomUUID()}.csv`);
  writeFileSync(tmp, csv);
  try {
    execFileSync(
      "gum",
      [
        "table",
        "--print",
        "--border",
        "rounded",
        "--separator",
        "\t",
        "--file",
        tmp,
      ],
      { stdio: ["inherit", "inherit", "inherit"] },
    );
  } finally {
    try {
      unlinkSync(tmp);
    } catch {}
  }
}

export function printTable(csv) {
  if (hasGum()) {
    printGumTable(csv);
    return;
  }
  printPlainTable(csv);
}

export function printBox(text, options = {}) {
  const borderForeground = options.borderForeground ?? "212";
  const padding = options.padding ?? "1 2";

  if (!hasGum()) {
    console.log(text);
    return;
  }

  execFileSync(
    "gum",
    [
      "style",
      "--border",
      "rounded",
      "--padding",
      padding,
      "--border-foreground",
      borderForeground,
      text,
    ],
    { stdio: ["inherit", "inherit", "inherit"] },
  );
}
