# Metrics Workbench

Workshop demo app — an e-commerce data-analytics workbench that showcases
Jac's Object-Spatial Programming (OSP) model, `by llm` integration, and
load-bearing Python (pandas / statsmodels / pyod) interop.

See `docs/design.md` for the full design rationale and the OSP demonstration
matrix. This README covers the CLI and server modes; the root README and the
walkthrough cover the full-stack dashboard (`jac run --dev main.jac`).

## Layout

```
metrics-workbench/
├── jac.toml                    # project config; pip deps, byllm model
├── api.jac                     # OSP graph, walkers, def:pub API, CLI dispatch
├── analytics.py                # pandas / statsmodels / pyod helpers (sidecar)
├── main.jac                    # full-stack entry: registers walkers, mounts the client
├── web.jac / web.impl.jac      # the browser dashboard (client placement inferred from JSX)
├── data/
│   └── generate_synth.py       # synthetic e-commerce CSV generator
├── docs/
│   └── design.md               # the design spec
└── README.md                   # (this file)
```

## Prerequisites

- `jac` **0.37+** (tested on 0.37.23):
  `curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash`
- **devenv + direnv** (recommended on NixOS) — the repo root has
  `devenv.nix` + `.envrc` so `cd`-ing into it enters a shell with a
  **regular Python 3.14** (not `3.14t`), which is the ABI Jac's embedded
  runtime expects. Without this, `jac run` fails with
  `Unable to import required dependency numpy`. First-time setup:

  ```bash
  cd <repo-root>
  direnv allow            # authorize the .envrc
  # devenv boots the shell; python3 --version should say 3.14.x (no `t`)
  ```

- An LLM API key exported in the environment (`ANTHROPIC_API_KEY`,
  `OPENAI_API_KEY`, etc.), or a local model via `jac model` for offline mode.

## First-run setup for this project

```bash
cd metrics-workbench
seed-jac-venv                          # (NixOS) recreates .jac/venv against the devenv's Python
jac install                            # pandas / numpy / statsmodels / pyod + npm deps from jac.toml
```

The `seed-jac-venv` helper is defined in the repo's `devenv.nix`. Its job
is to ensure the venv Jac uses was created with a Python whose ABI matches
Jac's embedded `libpython3.14.so`. Skip it and you'll get "Unable to
import required dependency numpy" the first time you `jac run`.

## Smoke run

Generate sample data, then exercise the CLI end-to-end:

```bash
# 1. Generate ~90 days of synthetic e-commerce time-series (~129k rows)
#    (numpy comes from the project venv that `jac install` populated)
.jac/venv/bin/python data/generate_synth.py data/synth_ecom.csv

# 2. Stay in the project dir so jac.toml is picked up. This is a web-app
#    project, so a bare `jac run` serves it: `--no-serve` runs api.jac's
#    CLI dispatch instead.

# 3. Ingest and register the dataset
jac run --no-serve api.jac ingest sales data/synth_ecom.csv
jac run --no-serve api.jac datasets

# 4. Define two metrics (pandas expressions over the columns)
jac run --no-serve api.jac metric sales revenue 'gross_revenue - refunds' order_ts
jac run --no-serve api.jac metric sales latency page_load_ms_p95 order_ts

# 5. Preview + analyse
jac run --no-serve api.jac preview sales revenue 14
jac run --no-serve api.jac anomaly sales revenue 90
jac run --no-serve api.jac forecast sales revenue 30

# 6. Inspect what's on the graph — this exercises walkers
jac run --no-serve api.jac summary          # workspace_summary walker
jac run --no-serve api.jac runs sales revenue
jac run --no-serve api.jac lineage          # export_lineage walker

# 7. Ask the LLM to narrate a run (needs an API key)
jac run --no-serve api.jac runs sales revenue                # copy a run jid prefix
jac run --no-serve api.jac narrate sales revenue <jid-prefix>

# 8. The agentic walker
jac run --no-serve api.jac investigate "why did revenue dip in mid-May?"

# 9. Housekeeping walkers
jac run --no-serve api.jac refresh 3         # refresh_stale_analyses walker
jac run --no-serve api.jac prune             # prune_orphan_insights walker
```

## Which command exercises which OSP feature

| Command | OSP feature it demonstrates |
|---|---|
| `ingest`, `metric`, `anomaly`, `forecast` | Typed nodes/edges + `def:pub` functions (flat CRUD) |
| `datasets`, `runs` | Graph filters `[root-->][?:Type]` and typed-edge traversal `[m ->:AnalyzedBy:->]` |
| `summary` | `walker workspace_summary` — nested `visit [-->]` recursion |
| `refresh` | `walker refresh_stale_analyses` — walker MODIFIES the graph as it walks |
| `prune` | `walker prune_orphan_insights` — `disengage` + destructive traversal |
| `lineage` | `walker export_lineage` — typed `has reports` field |
| `investigate` | `walker investigate` — **`by llm` inside a walker ability** (agentic OSP) |
| `narrate` | One-shot `def ... by llm` returning a typed `InsightPayload` |

## Server mode

```bash
jac run main.jac                       # boot the HTTP server + dashboard on :8000
jac run --dev main.jac                 # same, with hot reload
jac run --port 8765 main.jac           # custom port (serve flags go before the file)
jac run --faux main.jac                # print the auto-generated API without booting
```

Endpoints:

- `GET /functions` and `GET /walkers` — enumerate what's exposed.
- `POST /function/<name>` — call a `def:pub` function.
- `POST /walker/<name>` — spawn a walker.
- `GET /` — API self-description.
- `POST /user/register`, `POST /user/login` — auth. `:protect` walkers
  (the dashboard's `wb_*` walkers and the five OSP walkers above) need a
  JWT and run on the caller's own root; plain `def`/`walker` declarations
  are private helpers and are never served.

## Troubleshooting

- **`jac install` dies with `_posixsubprocess ... symbol not found in flat
  namespace '_PyExc_MemoryError'`** (jac 0.37.23 on macOS arm64). The
  binary's bundled Python can't create the project venv. Pre-create it with
  any regular CPython 3.14, then re-run: `python3.14 -m venv .jac/venv &&
  jac install` (`uv python install 3.14` gets you one).
- **`Unable to import required dependency numpy` under `jac run`.**
  The venv was seeded with the wrong Python ABI (probably `3.14t`
  free-threaded, but Jac embeds regular 3.14). Fix from the repo root:
  `direnv allow`, then `cd metrics-workbench && seed-jac-venv && jac install`.
- **`by llm` fails with a ConfigurationError.** Set an API key
  (`ANTHROPIC_API_KEY` etc.) or use a local model (`jac model`). See
  `[byllm.model]` in `jac.toml` for how to change the default model.
- **`ensurepip is not available` from `jac install`.** Jac's embedded
  Python doesn't ship ensurepip. `seed-jac-venv` pre-creates the venv
  with a full Python so this path is never taken.
