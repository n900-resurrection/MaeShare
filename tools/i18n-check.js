#!/usr/bin/env node
// Checks the translations of MaeShare (run: make i18n-check):
//  1. every language table P.<lang> of src/app/qml/i18n.js has exactly the keys of P.en, and the same %1 %2 placeholders in every value;
//  2. every language of the table is listed in TAGS and has a name in NAMES;
//  3. every Chinese message string of src/app/transfer.h (the C++ side says its status text in Chinese, i18n.js maps it to a key) has an entry in the CN map,
//     or is covered by a prefix/suffix rule, or is one of the two counted forms ("已选择 N 个文件", "已接收 N 个文件"). Otherwise it is shown in Chinese in every language.
// Exit code 1 when something is wrong.
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "..");
const src = fs.readFileSync(path.join(root, "src/app/qml/i18n.js"), "utf8");
const m = new Function(src + ";return {P, TAGS, NAMES, CN, PFX, SFX};")();
let errors = 0;
const err = (s) => { console.log("ERROR " + s); errors++; };
const ph = (s) => (String(s).match(/%\d/g) || []).sort().join(",");

const en = Object.keys(m.P.en);
for (const lang of Object.keys(m.P)) {
    if (lang === "en") continue;
    const keys = Object.keys(m.P[lang]);
    for (const k of en) if (!(k in m.P[lang])) err(lang + ": missing key " + k);
    for (const k of keys) if (!(k in m.P.en)) err(lang + ": extra key " + k);
    for (const k of en) if (k in m.P[lang] && ph(m.P.en[k]) !== ph(m.P[lang][k])) err(lang + ": placeholders of " + k + " differ (" + ph(m.P.en[k]) + " / " + ph(m.P[lang][k]) + ")");
    if (!m.TAGS.includes(lang)) err(lang + ": not in TAGS");
    if (!m.NAMES[lang]) err(lang + ": no name in NAMES");
}
for (const tag of m.TAGS) if (tag !== "system" && !m.P[tag]) err("TAGS lists " + tag + " but there is no table");

// Chinese string literals of transfer.h
const cjk = /[一-鿿]/;
const header = fs.readFileSync(path.join(root, "src/app/transfer.h"), "utf8").split("\n");
const counted = [/^已选择 %1 个文件$/, /^已接收 %1 个文件$/];
let checked = 0;
header.forEach((line, i) => {
    if (line.trim().startsWith("//")) return;
    for (const mm of line.matchAll(/"((?:[^"\\]|\\.)*)"/g)) {
        const s = mm[1];
        if (!cjk.test(s)) continue;
        checked++;
        if (s in m.CN || m.PFX.includes(s) || m.SFX.includes(s) || counted.some((r) => r.test(s))) continue;
        err("transfer.h:" + (i + 1) + ": no translation entry for \"" + s + "\" (add it to CN in i18n.js and a key to every language)");
    }
});
console.log(Object.keys(m.P).length + " languages, " + en.length + " keys, " + checked + " Chinese messages in transfer.h checked: " + (errors ? errors + " problem(s)" : "ok"));
process.exit(errors ? 1 : 0);
