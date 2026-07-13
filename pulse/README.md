# Pulse — the workshop live-build

A slim metric-anomaly narrator, **Jac-first**. The graph model, the z-score
anomaly scan (pure Jac), the `forecast`, and the LLM narration all live in
[api.jac](api.jac); [main.jac](main.jac) is the full-stack entry that mounts the
browser UI ([web.cl.jac](web.cl.jac)).

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
| `web.cl.jac` / `web.impl.jac` | the browser dashboard (compiled to React) |

## Try it — CLI (zero extra code)

```bash
jac install
jac enter main.jac seed                # generate a synthetic series in Jac
jac enter main.jac scan orders         # z-score (pure Jac) → {'anomalies': 4, 'indices': [30, 31, 32, 55]}
jac enter main.jac forecast orders 14  # linear_regression imported inline (interop)
jac enter main.jac narrate orders      # by llm → a typed Insight
```

> CLI args are **positional and arrive as strings** (`scan orders 3.0`, not
> `--threshold 3.0`). Numeric fields are coerced in the walker.

The graph **persists across calls** — `seed` then `scan` in separate invocations
works because everything hangs off `root`. That's the native-DB story, visible
from the CLI with no server.

## Try it — full-stack web (same walkers, +1 file)

```bash
jac start --dev main.jac               # → http://localhost:8000
```

The `.cl.jac` page calls the same walkers with `root spawn` — no fetch, no CORS.
Click **Narrate** and the LLM writes a typed `Insight` right in the browser.

## Config

`jac.toml` sets the `by llm` model (`claude-haiku-4-5-20251001`). Swap
`default_model` for a local model or MockLLM on airgapped / no-key machines.
