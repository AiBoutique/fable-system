# Portability adapter targets — verified API surfaces (as of 2026-07-16)

The concrete API facts the swappable platform adapters (`harness/adapters.py`)
target, so a live cross-model run is a one-command step once keys exist. Model
IDs churn fast (the research pass saw GPT-5.4→5.5 and Grok 4→4.3 within weeks), so
**adapters take the model ID explicitly** (`{"model": ...}` in the spec) — the IDs
below are documentation, not hardcoded defaults. Re-verify against the primary
sources when the currency-baseline entry ages out.

## Anthropic (host + reference bar) — `claude_cli` adapter
- Current tier: **Fable 5** (`claude-fable-5`, GA 2026-06-09, most capable widely released = the reference bar) / **Opus 4.8** (`claude-opus-4-8`, host) / **Sonnet 5** (`claude-sonnet-5`) / Haiku 4.5. Invite-only **Mythos 5** (`claude-mythos-5`). **No Opus 5.** Knowledge cutoff Jan 2026.
- Reached via the local `claude -p` CLI (no key handled). `effort` defaults to `high` on Opus 4.8 (all surfaces) and Sonnet 5 (API/Claude Code).
- Source: platform.claude.com/docs/en/docs/about-claude/models/overview (fetched 2026-07-16).

## xAI (Grok) — `grok` adapter
- Current IDs: **`grok-4.5`** (recommended; 500k context; knowledge cutoff 2026-02-01), **`grok-4.3`** (1M context), plus `grok-4.20-0309-reasoning` / `-non-reasoning` / `-multi-agent-0309`, `grok-build-0.1`.
- Base URL **`https://api.x.ai/v1`**; **OpenAI-SDK compatible** (set `baseURL` + `Authorization: Bearer <XAI_API_KEY>`). Our adapter posts to `/chat/completions` (the OpenAI-compatible path). NOTE: xAI's newer preferred endpoint is **`/responses`**; `/chat/completions` remains available and is the portable choice.
- Reasoning: **`reasoning_effort`** param, values low/medium/high, **default high**; cannot be disabled on grok-4.5.
- Key: `XAI_API_KEY` (env var, read at call time, never logged). Sources: docs.x.ai/developers/models, docs.x.ai/developers/grok-4-5 (fetched 2026-07-16).

## OpenAI — `openai` adapter
- Current flagship IDs: **`gpt-5.6`** (alias of `gpt-5.6-sol`, "frontier for complex professional work"), **`gpt-5.6-terra`** (balanced), **`gpt-5.6-luna`** (cost-optimized).
- Base URL **`https://api.openai.com/v1`**; our adapter posts to `/chat/completions`. NOTE: OpenAI now pushes the **Responses API** (`/responses`) as primary; `/chat/completions` remains available and is the portable choice.
- Reasoning effort levels exposed: none/low/medium/high/xhigh/max (parameter name per the reasoning guide; our adapter does not set it yet — see extension point below).
- Key: `OPENAI_API_KEY` (env var). Source: developers.openai.com/api/docs/models (fetched 2026-07-16).

## Adapter extension points (not wired; future work)
1. **Reasoning-effort passthrough.** Both vendors expose an effort dial (`reasoning_effort` / effort levels); a portable `spec["effort"]` → request-body field would let the harness test the effort dimension the research flagged. Deliberately omitted now to keep the body minimal and model-agnostic.
2. **`/responses` vs `/chat/completions`.** Both vendors now prefer `/responses`; the adapters use `/chat/completions` for maximum cross-vendor portability. If a target drops `/chat/completions`, add a `spec["endpoint"]` override (the base URL is already overridable via `spec["base_url"]` / `<NAME>_BASE_URL`).

## Local models — no API key needed (added 2026-07-17)

Any local OpenAI-compatible server (Ollama, LM Studio, llama.cpp server) works through the
`openai` adapter with an explicit keyless opt-in — the amplification question ("does the core
lift THIS model?") becomes runnable with zero cloud keys:

```
ollama serve                      # default http://localhost:11434/v1
python run.py --no-dry-run --model llama3.1:70b --conditions A0,A1 \
       --core ../core/portable-core.md --tasks tasks-calib-tight \
       --adapter-json '{"name":"openai","base_url":"http://localhost:11434/v1","allow_keyless":true}'
```

`allow_keyless` is honored ONLY for loopback base_urls (`localhost` / `127.0.0.1` / `[::1]`) —
a mistyped cloud call can never go out unkeyed; non-loopback still requires the env-var key,
and `--adapter-json` refuses credential-named fields outright (keys are env-only, never argv).
Dry-run verified end-to-end 2026-07-17 (4 cells, endpoint + adapter recorded in the runlog).

## To run a live cross-model measurement (blocked on user-supplied keys)
```
setx XAI_API_KEY <key>        # or export; the adapter reads it at call time
python run.py --no-dry-run --model grok-4.5 --conditions A0,A1 \
       --core ../core/portable-core.md --tasks tasks
```
Live cross-model behavior is **UNVERIFIED** until run with a real key — the harness never handles keys in plaintext, so this step is the user's to trigger.
