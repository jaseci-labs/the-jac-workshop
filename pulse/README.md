# Pulse — the workshop live-build

A slim metric-anomaly narrator, **Jac-first**. The graph model, the z-score
anomaly scan (pure Jac), the `forecast`, and the LLM narration all live in
[api.jac](api.jac); [main.jac](main.jac) is the full-stack entry that mounts the
browser UI ([web.jac](web.jac)).

It also shows **Python interop the first-class way**: `forecast` does
`import from statistics { linear_regression }` at the top of the `.jac` file and
uses it inline — one import, same file, no service, no glue. Swap the stdlib lib
for `pandas`/`numpy` (declare it in `jac.toml`) and it's the identical line.

Pulse is the app we build *live* and then fan out to every build target with a
near-zero diff. The **heavy** side of interop (pandas / pyod / statsmodels, kept
in a separate `analytics.py` — the escape-hatch flavor) lives in the sibling
[`../metrics-workbench`](../metrics-workbench) capstone.

## Graph

```
root ──▶ Series ──▶ Run ──▶ Insight
```

## Files

| File | Role |
|---|---|
| `api.jac` | the walkers (`seed`, `scan`, `forecast`, `narrate`, `series_points`) + `by llm` |
| `main.jac` | full-stack entry: imports the walkers, mounts the client |
| `web.jac` / `web.impl.jac` | the browser dashboard (compiled to React — client placement is inferred from the JSX) |

## Try it — CLI (zero extra code)

```bash
jac install
jac run --no-serve --entry seed main.jac                # generate a synthetic series in Jac
jac run --no-serve --entry scan main.jac orders         # z-score (pure Jac) → {'anomalies': 4, 'indices': [30, 31, 32, 55]}
jac run --no-serve --entry forecast main.jac orders 14  # linear_regression imported inline (interop)
jac run --no-serve --entry narrate main.jac orders      # by llm → a typed Insight
```

> `--no-serve` is needed because Pulse is a `web-app` project, so a bare
> `jac run` serves it. CLI args are **positional and arrive as strings**
> (`scan main.jac orders 3.0`, not `--threshold 3.0`). Numeric fields are
> coerced in the walker.

The graph **persists across calls** — `seed` then `scan` in separate invocations
works because everything hangs off `root`. That's the native-DB story, visible
from the CLI with no server.

## Try it — full-stack web (same walkers, +1 file)

```bash
jac run --dev main.jac                 # → http://localhost:8000
```

The `web.jac` page calls the same walkers with `root spawn` — no fetch, no CORS.
Click **Narrate** and the LLM writes a typed `Insight` right in the browser.

## Ship it (same source)

```bash
jac build --as wheel                   # → dist/pulse-0.1.0-py3-none-any.whl (pip-installable, runtime vendored)
jac build                              # → dist/pulse.jab, a sealed app bundle: `jac run pulse.jab`
```

The client target is picked by `jac.toml`, not a flag:

- **PWA** — add a `[client.pwa]` table (it needs at least one key, e.g.
  `theme_color = "#ff6a3d"`), then `jac setup && jac build --as client` →
  manifest + service worker + install banner in `.jac/client/dist/`.
- **Desktop** — set `kind = "desktop"` under `[project]`, then `jac build` →
  a native OS-webview app (no Electron) in `.jac/client/desktop/`.

## Config

`jac.toml` sets the `by llm` model (`claude-haiku-4-5-20251001`). Swap
`default_model` for a local model or MockLLM on airgapped / no-key machines.
