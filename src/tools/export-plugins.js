// export-plugins.js - record the machine's plugin state into the kit.
//
//   node export-plugins.js <claudeJsonPath> <knownMarketplacesPath> <outPath>
//
// Informational snapshot: marketplace plugins reinstall on a fresh machine
// via /plugin install <name>@<marketplace>; entries tagged "@inline" ship
// with the app/account and need no restore. No secrets are involved -
// only marketplace sources and plugin names are recorded.
'use strict';
const fs = require('fs');

const [, , claudeJson, marketsPath, out] = process.argv;
if (!claudeJson || !out) { console.error('usage: export-plugins.js <claudeJson> <knownMarketplaces> <outFile>'); process.exit(2); }

const strip = s => s.replace(/^﻿/, '');
const cur = JSON.parse(strip(fs.readFileSync(claudeJson, 'utf8')));

let markets = {};
if (marketsPath && fs.existsSync(marketsPath)) {
  const raw = JSON.parse(strip(fs.readFileSync(marketsPath, 'utf8')));
  for (const name of Object.keys(raw)) {
    markets[name] = { source: raw[name].source, lastUpdated: raw[name].lastUpdated };
  }
}
// A locally-added marketplace (directory/path source) would carry the machine's home
// path into a src-bound file; tokenize every string leaf like the MCP exporter does
// (r31; the step-2 scrub sweep stays the backstop, this stops the leak at the source).
const os = require('os');
const home = os.homedir();
const homeRe = new RegExp('^' + home.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?=$|[\\\\/])', 'i');
const tokenizeHome = v => (typeof v === 'string' && homeRe.test(v)) ? v.replace(homeRe, '<<HOME>>') : v;
const walkHome = o => {
  for (const k of Object.keys(o)) {
    const v = o[k];
    if (v && typeof v === 'object') walkHome(v);
    else o[k] = tokenizeHome(v);
  }
};
walkHome(markets);

const doc = {
  _comment: 'Plugin state at kit-build time. Marketplace plugins: /plugin install <name>@<marketplace>. ' +
    'Entries tagged @inline ship with the app/account - no restore needed.',
  exportedAt: (function () { const d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); })(),  // local date - keeps one build on one date (manifest stamps local too)
  marketplaces: markets,
  pluginsSeen: Object.keys(cur.pluginUsage || {})
};
fs.writeFileSync(out, JSON.stringify(doc, null, 2) + '\n', 'utf8');
console.log('marketplaces=' + Object.keys(markets).length + ' pluginsSeen=' + doc.pluginsSeen.length);
