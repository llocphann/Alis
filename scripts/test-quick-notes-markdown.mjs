#!/usr/bin/env node
// Native-free regression coverage for the Quick Notes source formatting policy
// and persistent default-title renumbering.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const markdown = fs.readFileSync(
    new URL("../modules/sidebarRight/notepad/MarkdownNote.js", import.meta.url), "utf8");
const context = {};
vm.runInNewContext(markdown, context, { filename: "MarkdownNote.js" });
const { format, safeReading } = context;
const apply = (source, patch) => source.slice(0, patch.from)
    + patch.insert + source.slice(patch.to);

let patch = format("hello", 0, 5, "underline");
assert.equal(apply("hello", patch), "<u>hello</u>");
assert.equal(apply("<u>hello</u>", format("<u>hello</u>", 3, 8, "underline")),
    "hello", "Ctrl+U toggles off when selecting the underlined content");

patch = format("one\nsecond", 6, 6, "align-center");
assert.equal(apply("one\nsecond", patch), 'one\n<p align="center">second</p>');
assert.equal(patch.selectionStart, patch.selectionEnd, "cursor stays collapsed");
assert.equal(patch.selectionStart, 'one\n<p align="center">'.length + 2,
    "cursor remains at the same logical character");

const centered = 'one\n<p align="center">second</p>';
patch = format(centered, centered.indexOf("cond"), centered.indexOf("cond"), "align-right");
assert.equal(apply(centered, patch), 'one\n<p align="right">second</p>');
assert.equal(apply('one\n<p align="right">second</p>',
    format('one\n<p align="right">second</p>', 23, 23, "align-left")),
    "one\nsecond", "left alignment removes the HTML paragraph wrapper");

const multi = "first\nsecond";
patch = format(multi, 0, multi.length, "align-justify");
assert.equal(apply(multi, patch),
    '<p align="justify">first</p>\n<p align="justify">second</p>');

assert.equal(safeReading("<u>hello</u>"), "<u>hello</u>");
assert.equal(safeReading('<p align="right">hello</p>'), '<p align="right">hello</p>');
assert.ok(safeReading('<img src="https://example.org/foo">').includes("&lt;img"));
assert.ok(safeReading('<script>alert(1)</script>').includes("&lt;script"));

const service = fs.readFileSync(
    new URL("../services/Notepad.qml", import.meta.url), "utf8");
const helper = service.match(/function _renumberDefaultTitles\(value\) \{([\s\S]*?)\n    \}\n\n    function _normalizeTabs/);
assert.ok(helper, "default title normalizer exists");
const renumber = vm.runInNewContext("(function(value) {" + helper[1] + "\n})");
const tabs = [
    { id: "keep-two", title: "Note 2", text: "important" },
    { id: "custom", title: "Meeting notes", text: "do not rename" }
];
const result = renumber(tabs);
assert.equal(result.changed, true);
assert.equal(result.tabs[0].title, "Note 1");
assert.equal(result.tabs[0].id, "keep-two");
assert.equal(result.tabs[0].text, "important");
assert.equal(result.tabs[1].title, "Meeting notes");
assert.equal(tabs[0].title, "Note 2", "input state is not mutated");
assert.equal(renumber(result.tabs).changed, false, "renumbering is idempotent");

console.log("ok - Quick Notes underline/alignment, safe preview and title normalization");
