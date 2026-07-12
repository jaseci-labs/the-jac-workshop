# Metrics Workbench

Workshop demo app — an e-commerce data-analytics workbench that showcases
Jac's Object-Spatial Programming (OSP) model, `by llm` integration, and
load-bearing Python (pandas / statsmodels / pyod) interop.

See `docs/design.md` for the full design rationale and the OSP demonstration
matrix. This README covers only how to run slice 1 (backend + CLI).

## Layout

```
metrics-workbench/
├── jac.toml                    # project config; pip deps, byllm model
├── src/
│   ├── main.jac                # OSP graph, walkers, def:pub API, CLI dispatch
│   └── analytics.py            # pandas / statsmodels / pyod helpers (sidecar)
├── data/
│   └── generate_synth.py       # synthetic e-commerce CSV generator
├── docs/
│   └── design.md               # the design spec
└── README.md                   # (this file)
```

The CLI is the target for slice 1. Fullstack web, desktop, and native
targets come in later slices.

## Prerequisites

- `jac` toolchain built or installed. On this repo's dev machine that's
  `~/Space/jaseci/jac/zig-out/bin/jac` (alias it as `jac`).
- **devenv + direnv** (recommended on NixOS) — the repo root has
  `devenv.nix` + `.envrc` so `cd`-ing into it enters a shell with a
  **regular Python 3.14** (not `3.14t`), which is the ABI Jac's embedded
  runtime expects. Without this, `jac start` fails with
  `Unable to import required dependency numpy`. First-time setup:

  ```bash
  cd <repo-root>
  direnv allow            # authorize the .envrc
  # devenv boots the shell; python3 --version should say 3.14.x (no `t`)
  ```

- An LLM API key exported in the environment (`ANTHROPIC_API_KEY`,
  `OPENAI_API_KEY`, etc.) or `jac install 'byllm[local]'` for offline mode.

## First-run setup for this project

```bash
cd metrics-workbench
seed-jac-venv                          # recreates .jac/venv against the devenv's Python
jac install pandas statsmodels pyod byllm
```

The `seed-jac-venv` helper is defined in the repo's `devenv.nix`. Its job
is to ensure the venv Jac uses was created with a Python whose ABI matches
Jac's embedded `libpython3.14.so`. Skip it and you'll get "Unable to
import required dependency numpy" the first time you `jac start`.

## Smoke run

Generate sample data, then exercise the CLI end-to-end:

```bash
# 1. Generate ~90 days of synthetic e-commerce time-series (~129k rows)
python data/generate_synth.py

# 2. Ensure you're in the project so jac.toml is picked up
# (already there from previous step)

# 3. Ingest and register the dataset
jac run src/main.jac ingest sales data/synth_ecom.csv
jac run src/main.jac datasets

# 4. Define two metrics (pandas expressions over the columns)
jac run src/main.jac metric sales revenue 'gross_revenue - refunds' order_ts
jac run src/main.jac metric sales latency page_load_ms_p95 order_ts

# 5. Preview + analyse
jac run src/main.jac preview sales revenue 14
jac run src/main.jac anomaly sales revenue 90
jac run src/main.jac forecast sales revenue 30

# 6. Inspect what's on the graph — this exercises walkers
jac run src/main.jac summary          # workspace_summary walker
jac run src/main.jac runs sales revenue
jac run src/main.jac lineage          # export_lineage walker

# 7. Ask the LLM to narrate a run (needs an API key)
jac run src/main.jac runs sales revenue                # copy a run jid prefix
jac run src/main.jac narrate sales revenue <jid-prefix>

# 8. The agentic walker
jac run src/main.jac investigate "why did revenue dip in mid-May?"

# 9. Housekeeping walkers
jac run src/main.jac refresh 3         # refresh_stale_analyses walker
jac run src/main.jac prune             # prune_orphan_insights walker
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

## What's missing in slice 1

Explicitly out of scope for this slice — planned for later slices:

- `cl` React UI (Perspective pivot + ECharts charts).
- `jac start` multi-user fullstack mode (walkers switch to `walker:priv`).
- `jac build --client desktop` target.
- `jac nacompile` native-binary target.
- Auth wiring.

## Server mode

```bash
jac start src/main.jac                 # boot the HTTP server on :8000
jac start src/main.jac --port 8765     # custom port
jac start src/main.jac --faux          # print the auto-generated API without booting
```

Endpoints:

- `GET /functions` and `GET /walkers` — enumerate what's exposed.
- `POST /function/<name>` — call a `def:pub` function.
- `POST /walker/<name>` — spawn a walker.
- `GET /` — API self-description.
- `POST /user/register`, `POST /user/login` — auth (needed once `def:priv`
  / `walker:priv` are introduced in slice 2).

Verified locally: the server boots, exposes 27 functions + 5 walkers, and
`POST /function/list_datasets` returns `{"result": [], "reports": []}` on
a fresh graph.

## Troubleshooting

- **`Unable to import required dependency numpy` under `jac start`.**
  The venv was seeded with the wrong Python ABI (probably `3.14t`
  free-threaded, but Jac embeds regular 3.14). Fix from the repo root:
  `direnv allow`, then `cd metrics-workbench && seed-jac-venv && jac install`.
- **`by llm` fails with a ConfigurationError.** Set an API key
  (`ANTHROPIC_API_KEY` etc.) or run `jac install 'byllm[local]'`. See
  `[plugins.byllm.model]` in `jac.toml` for how to change the default model.
- **`ensurepip is not available` from `jac install`.** Jac's embedded
  Python doesn't ship ensurepip. `seed-jac-venv` pre-creates the venv
  with a full Python so this path is never taken.
