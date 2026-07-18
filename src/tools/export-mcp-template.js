// export-mcp-template.js - build mcp-servers.template.json from a live
// ~/.claude.json, redacting anything secret-shaped so the kit stays clean
// enough to store on cloud/USB, and tokenizing the home directory so the
// template is username-portable.
//
//   node export-mcp-template.js <claudeJsonPath> <outTemplatePath>
//
// Redaction rules (value classes, not just alphabets):
//  - every env var value and every header value -> "<<SET-ME>>"
//  - url: the entire userinfo (token-as-username included), everything after
//    the first ?/# separator, and any path segment that is JWT-shaped,
//    key-prefixed (sk-/sk_ style), or opaque-token-shaped are redacted; the
//    authority (host) is never rewritten. Conservative by design: a benign
//    32+ char opaque path segment (e.g. a UUID-ish id) is also redacted -
//    hand-restore it from the provider console.
//  - args: redacted when (a) the previous arg is a credential-named flag
//    (--token/--key/--api-key/--password/--secret/--auth/--bearer/...),
//    (b) the value itself is credential-shaped: JWT (x.y.z base64url),
//    scheme://user:pass@ connection string, ?key=/&token=-style query,
//    known key prefixes (sk-, ghp_, gho_, xox?-, AKIA, ASIA; 8+ char suffix),
//    or a 32+ char bare token that is not an existing filesystem path;
//    or (c) the arg is NAME=VALUE / --flag=VALUE where the name is
//    credential-ish, or it follows -e/--env (env values are opaque here,
//    same as the env{} block)
//  - any string that starts with the exporting user's home dir -> "<<HOME>>..."
//    (the installer substitutes the target machine's home at install time)
'use strict';
const fs = require('fs');
const os = require('os');

const [, , src, out] = process.argv;
if (!src || !out) { console.error('usage: export-mcp-template.js <claudeJson> <outFile>'); process.exit(2); }

let redacted = 0;
const SETME = '<<SET-ME>>';
const home = os.homedir();
// boundary lookahead: only a true descendant path (or the home itself)
// tokenizes - siblings like C:\Users\alexandria (vs home C:\Users\alexandr) must never match
const homeRe = new RegExp('^' + home.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?=$|[\\\\/])', 'i');

const CRED_FLAG = /^--?(api[-_]?key|key|token|secret|password|passwd|pwd|pass|passphrase|auth(orization)?|bearer|credential[s]?|access[-_]?token|client[-_]?secret|refresh[-_]?token|header)$/i;
const CRED_NAME = /(^|[-_])(api[-_]?key|key|token|secret|password|passwd|pwd|pass|passphrase|auth(orization)?|bearer|credential[s]?)([-_]|\d|$)/i;
// names like --auth-mode/--token-type carry a scheme choice, not a secret
const AUTH_META = /(mode|type|method|scheme|flow)$/i;
const ENV_FLAG = /^--?e(nv)?$/;
const ENV_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;
const JWT = /eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}(\.[A-Za-z0-9_-]{4,})?/;
// Google classes (AIza..., ya29....) are matched here rather than left to
// BARE_TOKEN: BARE_TOKEN is whole-arg anchored, so a ya29 token (its '.' breaks
// the charset) and either class embedded in a URL path or compound arg leaked
// through - all three reproduced by execution, 2026-07-18. The refresh-kit scrub
// gate names both classes, so the exporter must cover them.
const KEY_PREFIX = /\b(sk|rk|pk)[-_][A-Za-z0-9_-]{8,}|\bgh[pousr]_[A-Za-z0-9]{8,}|\bxox[a-z]-[A-Za-z0-9-]{8,}|\b(AKIA|ASIA)[A-Z0-9]{8,}|\bAIza[A-Za-z0-9_-]{8,}|\bya29\.[A-Za-z0-9._-]{8,}/;
const QUERY_SECRET = /[?&][^=&\s]*(key|token|secret|password|auth)[^=&\s]*=/i;
// A credential field inside a ;-delimited connection string. Two shapes, both
// requiring the cred word to sit immediately before '=' (so "design=grid",
// which merely contains "sig", is NOT a hit): CONN_SECRET matches a key after a
// delimiter; CONN_LEADING matches a LEADING key (--conn=Password=x;...) but only
// when a ';' proves it is a connection string, so a plain "--api-key=SECRET"
// arg is left to the name-preserving '=' handler, not whole-arg redacted
// (2026-07-17 fresh-eyes review: the earlier '^'-anchored single pattern
// over-redacted --api-key=value to <<SET-ME>>, dropping the flag name).
const CONN_SECRET = /[;&?][^;&\s=]*(key|token|secret|password|passwd|pwd|signature|sas)=[^;&\s]/i;
const CONN_LEADING = /^[^;&\s=]*(key|token|secret|password|passwd|pwd|signature|sas)=[^;&\s=]*;/i;
const CONN_USERINFO = /^[a-z][a-z0-9+.-]*:\/\/[^/\s:@]+:[^@\s]+@/i;
const BARE_TOKEN = /^[A-Za-z0-9+/=_-]{32,}$/;
// user:pass value shape (curl -u / --user), but NOT a filesystem path
// (python -u <script> and drive/slash paths must survive)
const USERPASS = /^[^\s:\\/]+:[^\s\\/]+$/;
// an auth-carrying HTTP header value (curl -H); a benign Content-Type must survive
const AUTH_HEADER = /(bearer|authoriz|api[-_]?key|x-[a-z-]*(key|auth|token)|\btoken\b|secret|password|cookie)/i;

// A credential-carrying flag, in space-separated form (`--auth-token SECRET`).
// CRED_FLAG's full-match alternatives miss COMPOUND names (--auth-token,
// --api-token); reuse CRED_NAME's substring logic (which the `=` form already
// uses) so both forms agree (2026-07-17 review: compound flags leaked).
function credFlag(flag) {
  if (typeof flag !== 'string' || flag[0] !== '-') return false;
  const bare = flag.replace(/^--?/, '');
  if (AUTH_META.test(bare)) return false;                   // --auth-mode / --token-type select a scheme, not a secret
  return CRED_FLAG.test(flag) || CRED_NAME.test(bare);
}

// -u/--user and -H are OVERLOADED: -u is also python's unbuffered flag and -H is
// only sensitive for auth-ish headers, so gate redaction on the VALUE's shape
// rather than the flag alone (2026-07-17 review: unconditional -u broke
// `python -u server.py`; --user user:pass leaked).
function credByFlagAndValue(flag, val) {
  if (typeof val !== 'string') return false;
  if (flag === '-H') return AUTH_HEADER.test(val);           // -H auth header (--header stays unconditional via CRED_FLAG)
  if (flag === '-u' || flag === '--user') return USERPASS.test(val) && !fs.existsSync(val);
  return false;
}

function looksSecret(v) {
  if (typeof v !== 'string' || v.length < 8) return false;
  if (JWT.test(v)) return true;
  if (KEY_PREFIX.test(v)) return true;
  if (CONN_USERINFO.test(v)) return true;
  if (QUERY_SECRET.test(v)) return true;
  if (CONN_SECRET.test(v) || CONN_LEADING.test(v)) return true;
  if (BARE_TOKEN.test(v) && !fs.existsSync(v)) return true;
  return false;
}
function scrubUrl(u) {
  let s = u;
  // entire userinfo - with or without a password; a token-as-username is a secret too
  if (/:\/\/[^/\s@]+@/.test(s)) { s = s.replace(/(:\/\/)[^/\s@]+@/, '$1' + SETME + '@'); redacted++; }
  // everything after the FIRST ?/# separator goes - a fragment containing '?'
  // must not re-enter query handling with its prefix kept
  const q = s.indexOf('?'), h = s.indexOf('#');
  const cut = q < 0 ? h : (h < 0 ? q : Math.min(q, h));
  if (cut >= 0) { s = s.slice(0, cut + 1) + SETME; redacted++; }
  // path segments only (authority never rewritten - hostnames that merely
  // contain a key-like substring must survive): JWT-shaped, key-prefixed,
  // or opaque-token-shaped segments are redacted
  const parts = s.split('/');
  for (let i = 3; i < parts.length; i++) {
    if (parts[i] && parts[i] !== SETME && (JWT.test(parts[i]) || KEY_PREFIX.test(parts[i]) || looksSecret(parts[i]))) {
      parts[i] = SETME; redacted++;
    }
  }
  return parts.join('/');
}
function tokenizeHome(v) {
  if (typeof v === 'string' && homeRe.test(v)) return v.replace(homeRe, '<<HOME>>');
  return v;
}

const cur = JSON.parse(fs.readFileSync(src, 'utf8').replace(/^﻿/, ''));
const servers = cur.mcpServers || {};
const tpl = {};

for (const name of Object.keys(servers)) {
  const s = JSON.parse(JSON.stringify(servers[name])); // deep copy
  if (s.env) for (const k of Object.keys(s.env)) { s.env[k] = SETME; redacted++; }
  if (s.headers) for (const k of Object.keys(s.headers)) { s.headers[k] = SETME; redacted++; }
  if (typeof s.url === 'string') { s.url = tokenizeHome(scrubUrl(s.url)); }
  if (typeof s.command === 'string') { s.command = tokenizeHome(looksSecret(s.command) ? SETME : s.command); }
  if (typeof s.cwd === 'string') { s.cwd = tokenizeHome(s.cwd); }
  if (Array.isArray(s.args)) {
    let prevArg = '';
    s.args = s.args.map(a => {
      if (typeof a !== 'string') { prevArg = ''; return a; }
      const credByFlag = credFlag(prevArg) || credByFlagAndValue(prevArg, a);
      const envByFlag = ENV_FLAG.test(prevArg);
      prevArg = a;
      if (credByFlag || looksSecret(a)) { redacted++; return SETME; }
      const eq = a.indexOf('=');
      if (eq > 0) {
        const name = a.slice(0, eq), val = a.slice(eq + 1);
        if (ENV_FLAG.test(name)) {
          // joined form: -e=NAME=VALUE / --env=NAME=VALUE
          const eq2 = val.indexOf('=');
          if (eq2 > 0 && ENV_NAME.test(val.slice(0, eq2))) { redacted++; return name + '=' + val.slice(0, eq2) + '=' + SETME; }
        } else if (val && (CRED_FLAG.test(name) || (CRED_NAME.test(name) && !AUTH_META.test(name)) || (envByFlag && ENV_NAME.test(name)) || looksSecret(val))) {
          // env values are opaque only for env-var-shaped names - a script
          // after `node -e` must not be mistaken for NAME=VALUE
          redacted++;
          return name + '=' + SETME;
        }
      }
      return tokenizeHome(a);
    });
  }
  tpl[name] = s;
}

const doc = {
  _comment: 'User-scope MCP servers exported from ~/.claude.json. Secret-shaped values are redacted to <<SET-ME>>; ' +
    'the exporting home directory is tokenized to <<HOME>> and substituted at install time, so the template survives a username change. ' +
    'stdio servers point at locally installed programs - reinstall the app first or the server stays disconnected. ' +
    'Manual alternative: claude mcp add --scope user <name> <command...>',
  exportedAt: (function () { const d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); })(),  // local date - keeps one build on one date (manifest stamps local too)
  mcpServers: tpl
};
fs.writeFileSync(out, JSON.stringify(doc, null, 2) + '\n', 'utf8');
console.log('servers=' + Object.keys(tpl).length + ' redactions=' + redacted);
