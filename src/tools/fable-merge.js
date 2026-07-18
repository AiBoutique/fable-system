// fable-merge.js - safe JSON merges for the fable installer.
// Node is used because it round-trips any valid JSON (including keys
// PowerShell 5.1's parser rejects, and non-ASCII content 5.1 would
// re-encode) without reshaping untouched content.
//
//   node fable-merge.js hooks <targetSettingsJson> <kitSettingsJson>
//     Adds the kit's hook groups to the target (deduped by exact command
//     string) and copies the kit's benign prefs only where absent.
//     Superseded fable hook variants — same stable marker phrase, different
//     command — are REPLACED by the kit's version (backup is taken by the
//     installer first); foreign hooks are never touched.
//     A malformed non-array hooks.<event> on the target is wrapped, never
//     discarded (persisted only when the merge changes content - a
//     no-change run leaves the target byte-untouched).
//
//   node fable-merge.js mcp <targetClaudeJson> <mcpTemplateJson> [homeDir]
//     Adds template mcpServers entries absent from the target; creates the
//     target file if missing. Never overwrites an existing server entry.
//     Every "<<HOME>>" token in template strings is replaced with homeDir
//     (default: this user's home) so templates are username-portable.
//
// Prints MERGED / NOCHANGE / ADDED:<names> on success; exits non-zero on error.
'use strict';
const fs = require('fs');
const os = require('os');

function read(p) { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, '')); }
function write(p, o) { fs.writeFileSync(p, JSON.stringify(o, null, 2) + '\n', 'utf8'); }
function substHome(v, home) {
  if (typeof v === 'string') return v.split('<<HOME>>').join(home);
  if (Array.isArray(v)) return v.map(x => substHome(x, home));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = substHome(v[k], home);
    return o;
  }
  return v;
}

const [, , mode, target, src, homeArg] = process.argv;
if (!mode || !target || !src) { console.error('usage: fable-merge.js <hooks|mcp> <target> <source> [homeDir]'); process.exit(2); }

if (mode === 'hooks') {
  const kit = read(src);
  let cur = fs.existsSync(target) ? read(target) : {};
  cur.hooks = cur.hooks || {};
  let changed = false;
  // A hook is a replaceable fable variant only if it carries BOTH the marker
  // AND the fable action-signature phrase - a foreign hook that merely
  // references the marker (log counters, dashboards) never matches.
  // ASSUMPTION (r31): kit hook groups are single-command by construction - one command
  // per group in settings.json. The missing-command check further down pushes a kit
  // group WHOLE when any of its commands is absent; a future multi-command kit group
  // would need per-command filtering there or it duplicates already-present commands.
  const MARKERS = {
    SessionStart: { m: "Standing order (user settings hook)", s: "invoke the fable-mode skill" },
    UserPromptSubmit: { m: "Prompt classifier (user hook)", s: "invoke the fable-mode skill" },
    SubagentStart: { m: "Standing order (user hook)", s: "verify claims by execution" }
  };
  for (const ev of Object.keys(kit.hooks || {})) {
    if (!Array.isArray(cur.hooks[ev])) cur.hooks[ev] = (cur.hooks[ev] === undefined || cur.hooks[ev] === null) ? [] : [cur.hooks[ev]];
    const kitCmds = new Set();
    for (const g of (kit.hooks[ev] || [])) for (const h of ((g && g.hooks) || [])) if (h.command) kitCmds.add(h.command);
    const marker = MARKERS[ev];
    if (marker) {
      for (const g of cur.hooks[ev]) {
        if (!g || !Array.isArray(g.hooks)) continue;
        const n = g.hooks.length;
        g.hooks = g.hooks.filter(h => !(h && h.command && h.command.includes(marker.m) && h.command.includes(marker.s) && !kitCmds.has(h.command)));
        if (g.hooks.length !== n) changed = true;
      }
      const nGroups = cur.hooks[ev].length;
      // drop null/degenerate groups too, not just emptied ones: a literal null in the event
      // array would otherwise be re-serialized here while the PowerShell fallback drops it,
      // leaving the two merge implementations disagreeing on the same input
      cur.hooks[ev] = cur.hooks[ev].filter(g => g && !(Array.isArray(g.hooks) && g.hooks.length === 0));
      if (cur.hooks[ev].length !== nGroups) changed = true;
    }
    const have = new Set();
    for (const g of cur.hooks[ev]) for (const h of ((g && g.hooks) || [])) if (h.command) have.add(h.command);
    for (const g of (kit.hooks[ev] || [])) {
      const cmds = (g.hooks || []).map(h => h.command).filter(Boolean);
      if (cmds.some(c => !have.has(c))) { cur.hooks[ev].push(g); changed = true; }
    }
  }
  for (const k of ['autoUpdatesChannel', 'theme', 'skipWorkflowUsageWarning']) {
    if (kit[k] !== undefined && cur[k] === undefined) { cur[k] = kit[k]; changed = true; }
  }
  if (changed || !fs.existsSync(target)) write(target, cur);  // no-change runs leave the target byte-untouched
  console.log(changed ? 'MERGED' : 'NOCHANGE');
} else if (mode === 'mcp') {
  const home = homeArg || os.homedir();
  const tpl = read(src);
  let cur = fs.existsSync(target) ? read(target) : {};
  cur.mcpServers = cur.mcpServers || {};
  const added = [];
  for (const name of Object.keys(tpl.mcpServers || {})) {
    if (!Object.prototype.hasOwnProperty.call(cur.mcpServers, name)) {
      cur.mcpServers[name] = substHome(tpl.mcpServers[name], home);
      added.push(name);
    }
  }
  if (added.length || !fs.existsSync(target)) write(target, cur);  // no-change runs leave the target byte-untouched
  console.log(added.length ? 'ADDED:' + added.join(',') : 'NOCHANGE');
} else {
  console.error('unknown mode: ' + mode);
  process.exit(2);
}
