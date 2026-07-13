# Pulse — the workshop live-build

A slim metric-anomaly narrator, **Jac-first**. The graph model, the z-score
anomaly scan (pure Jac), the `forecast`, and the LLM narration all live in one
file: [src/main.jac](src/main.jac).

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

## Try it (CLI — zero extra code)

```bash
jac enter src/main.jac seed              # generate a synthetic series in Jac
jac enter src/main.jac list_series
jac enter src/main.jac scan orders       # z-score (pure Jac) → {'anomalies': 4, 'indices': [30, 31, 32, 55]}
jac enter src/main.jac forecast orders 14 # linear_regression imported inline (interop)
jac enter src/main.jac narrate orders    # LLM writes an Insight (needs a model / MockLLM)
```

> CLI args are **positional and arrive as strings** (`scan orders 3.0`, not
> `--threshold 3.0`). Numeric fields are coerced in the walker.

The graph **persists across calls** — `seed` then `scan` in separate invocations
works because everything hangs off `root`. That's the native-DB story, visible
from the CLI with no server.

## Other targets (same source)

```bash
jac start src/main.jac                    # every :pub walker → POST /walker/<Name>
jac start src/main.jac --client web       # + a .cl.jac page (to build)
jac nacompile src/main.jac                # native binary, no Python runtime
```

## Config

`jac.toml` sets the `by llm` model. Swap `default_model` for a local model or
MockLLM on airgapped / no-key machines.
