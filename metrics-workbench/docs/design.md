# Metrics Workbench — Workshop Demo App

A data-analytics application for **e-commerce operations** that showcases Jac's
end-to-end story: one language, one source, one deploy — spanning CLI, fullstack
web, desktop, and native binary targets, with load-bearing Python and JavaScript
package interop.

Audience: **enterprise software developers**. The framing assumes familiarity
with Python, JS/React, REST APIs, and typical "we already have a stack" concerns
(auth, persistence, deployment).

---

## 1. The Pitch

Point the app at a CSV or parquet of business time-series (orders, revenue,
refunds, page-load latency, error rates) and get:

- Interactive pivoting and filtering over millions of rows.
- Anomaly detection on any metric, any window.
- Forecasts with confidence intervals and seasonality decomposition.
- An LLM-written narrative explaining what changed and why it might matter.

Same source compiles to:

- **CLI** for scripted / CI use.
- **Fullstack web app** for a shared analyst workbench.
- **Desktop app** for offline / airgapped analysis.
- **Native binary** for fast batch runs.

---

## 2. Why This Example

The example is deliberately chosen so that **each ecosystem does what only it
can do well**. Nothing on either side is decorative — swap a package out and the
app genuinely gets worse.

### 2.1 Python's Role (Load-Bearing)

| Package | What it does | Why not JS |
|---|---|---|
| `pandas` | Ingest, resample, groupby, join, expression evaluation on tabular data | JS has no serious dataframe library. Danfo.js and arquero are toys by comparison. |
| `statsmodels` (SARIMAX / STL) or `prophet` | Time-series forecasting with confidence intervals and seasonality decomposition | JS has no peer-reviewed statistical forecasting library. |
| `pyod` or `scipy.stats` | Anomaly detection — dozens of algorithms (IForest, LOF, ECOD, KNN, ...) | No mature JS anomaly-detection stack. |
| `duckdb` (optional) | Analytical SQL over dataframes and parquet | duckdb-wasm exists but Python bindings are the reference implementation. |

### 2.2 JavaScript's Role (Load-Bearing)

| Package | What it does | Why not Python |
|---|---|---|
| `@finos/perspective` | WASM-powered 60fps pivot / filter / group over millions of rows in the browser | Python cannot render interactive tables in the browser. FINOS pedigree lands with enterprise. |
| `echarts-for-react` | Enterprise dashboards — brush/zoom, tooltips, anomaly markers, forecast bands, streaming updates | Python plotly-in-browser is a pale shadow of ECharts' interactivity budget. |
| `@tanstack/react-table` (optional) | Virtualized run-history list, sortable columns | Python has no client-side rendering story. |

### 2.3 What OSP Demonstrates

The example is designed so **Object-Spatial Programming** is not a bolted-on
graph model but the natural expression of the domain. See section 4.2 for
the walker catalog; the OSP features specifically exercised:

| OSP feature | Where it lives |
|---|---|
| Typed `node` declarations | `Dataset`, `Metric`, `AnalysisRun`, `Insight` |
| Typed `edge` with declared endpoints | `Derives`, `AnalyzedBy`, `NarratedBy` — endpoints let outgoing traversals infer the target type without `[?:Type]` postfilters |
| `has` fields on both nodes and edges | Edges carry provenance metadata (expression, kind, run_at, model) that `edge-filter` traversals can predicate on |
| Persistence off `root` | No database code; nodes reachable from root persist under SQLite locally, MongoDB under `--scale` |
| Per-user graph isolation | Under `jac start`, each analyst's workbench is invisible to others; the same code that runs locally serves multi-user without changes |
| `visit [-->]` for nested recursion | `workspace_summary` and `export_lineage` traverse the whole DAG without manual loops |
| `here` and `self` | Every walker ability uses `here` for the current node and `self` for walker state |
| `report` and typed `has reports` | All walkers return typed structured data; the CLI serializes with `--json` |
| `disengage` | `prune_orphan_insights` short-circuits when a valid ancestor is found |
| Walker modifying the graph as it moves | `refresh_stale_analyses` spawns fresh detections in place while walking |
| `by llm` inside a walker ability | `investigate` uses the LLM to decide `visit` targets — the agentic OSP pattern |

### 2.4 What Jac Adds

Jac unifies the two ecosystems in one source without the traditional glue:

- No CORS config, no FastAPI decorator boilerplate, no Pydantic schema
  duplicated as TypeScript interfaces, no `fetch()` wrapper.
- No `useState` / `useEffect` plumbing — reactive `has` fields and lifecycle
  abilities on the UI side.
- Per-user graph isolation is a runtime property, not code you write.
- The same `walker` is a CLI subcommand, a REST endpoint, and a callable RPC
  from the frontend.

---

## 3. Graph Model

The domain graph expresses **data lineage** — a small, opinionated DAG of four
node types. This is what makes Jac's graph model feel native to the domain
instead of bolted on.

```
Dataset ──(derives)──▶ Metric ──(analyzed_by)──▶ AnalysisRun ──(narrated_by)──▶ Insight
```

### 3.1 Nodes

- **`Dataset`** — a raw CSV/parquet ingested by the user.
  Fields: `name`, `source_path`, `row_count`, `columns[]`, `ingested_at`.
- **`Metric`** — a named, typed quantity derived from a dataset via a pandas
  expression.
  Fields: `name`, `expression`, `dtype`, `time_column`, `unit`.
- **`AnalysisRun`** — the result of executing an analysis (anomaly detection or
  forecast) on a metric over a window.
  Fields: `kind` (`anomaly` | `forecast`), `params`, `window`, `output`
  (structured result), `duration_ms`, `run_at`.
- **`Insight`** — an LLM-authored narrative describing what a run found.
  Fields: `summary`, `bullets[]`, `confidence`, `authored_by` (model id),
  `authored_at`.

### 3.2 Edges

All three are **typed edges** — they carry their own data so `edge-filter`
traversals have something to filter on. Endpoint types are declared, so
outgoing traversals infer the target type without a `[?:Type]` postfilter.

- **`edge Derives: Dataset --> Metric`** — carries the pandas `expression`
  string used to compute the metric and the `time_column`.
- **`edge AnalyzedBy: Metric --> AnalysisRun`** — carries the `kind`
  (`"anomaly"` or `"forecast"`) and `run_at` so we can filter by recency
  without loading the run node itself.
- **`edge NarratedBy: AnalysisRun --> Insight`** — carries the `model` id
  used and the narration timestamp.

### 3.3 Per-User Root

Every analyst's workbench hangs off their own `root`. Datasets uploaded by one
user are invisible to another. This is a runtime guarantee, not application
code — see the `per-user-graph` entry in the Sirno lake.

---

## 4. API Surface — Functions and Walkers

Jac exposes server logic two ways: `def:pub` **functions** and **walkers**.
Per the OSP reference:

> Functions *reach into* a graph from the outside and return a value. Walkers
> *move through* a graph, accumulating state, reporting along the way. For a
> flat structure, the function form is more concise. Walkers earn their keep
> when the graph is deeper.

The workbench uses both. This is a deliberate teaching point: **not every
endpoint should be a walker**. Flat CRUD is cleaner as a function.

### 4.1 Functions (`def:pub` — Flat CRUD, One-Shot Ops)

| Function | Purpose | Python packages used |
|---|---|---|
| `ingest_dataset(path)` | Load a CSV/parquet, create `Dataset` node, sample rows for preview | `pandas` |
| `list_datasets()` | Enumerate the user's datasets — `[root-->][?:Dataset]` | — |
| `define_metric(dataset, name, expression, time_column)` | Attach a `Metric` to a `Dataset` via a typed `Derives` edge | `pandas` |
| `preview_metric(metric, n)` | Return the first N rows of a metric as JSON | `pandas` |
| `detect_anomalies(metric, window, algorithm)` | Run `pyod` on a metric slice, produce an `AnalysisRun` | `pyod` |
| `forecast(metric, horizon, seasonality)` | Run `statsmodels` (SARIMAX/STL) on a metric, produce an `AnalysisRun` with prediction intervals | `statsmodels` |
| `list_runs(metric)` | History of `AnalyzedBy` edges, sorted by recency | — |
| `narrate(run) by llm` | Ask the LLM to write an `Insight` for a run | Jac `by llm` |
| `delete_dataset(dataset)` | Remove a dataset and its derived subgraph | — |

These are the app's primary REST surface. Each one touches at most a handful
of adjacent nodes — walker semantics would be overkill.

### 4.2 Walkers (OSP — Traversal Earns Its Keep)

Walkers show up when the operation is **fundamentally about walking the DAG**
— visiting many nodes across the lineage, accumulating state at each,
modifying the graph as they move, or making agentic decisions at each hop.

| Walker | Traversal shape | What it demos |
|---|---|---|
| `walker workspace_summary` | `Root entry: visit [-->]` → `Dataset entry: visit [-->]` → `Metric entry: visit [-->]` → `AnalysisRun entry: collect` | Nested recursion via `visit [-->]` with no manual loops; typed report field aggregates a nested structured summary |
| `walker refresh_stale_analyses` | Walks the DAG, at each `Metric` checks the most recent `AnalysisRun` age; if stale (>N days), spawns a fresh `detect_anomalies` in place before continuing | **Walker modifying the graph as it moves** — the canonical OSP pattern |
| `walker prune_orphan_insights` | Visits every `Insight`; if it still has an incoming `NarratedBy` edge from a valid run, `disengage`s; otherwise deletes | Demos `disengage` and destructive traversal for cleanup jobs |
| `walker investigate(question: str) by llm` | Starts at a `Metric`; at each node the walker uses `by llm` **inside an entry ability** to decide `visit` where next (look at recent runs? hop to sibling metrics via shared dataset? stop and narrate?); reports an `Insight` | **The agentic OSP pattern** — nodes as states, edges as transitions, walker + `by llm` as agent. This is the Welcome page's headline OSP-with-AI story. |
| `walker export_lineage` | Full DAG walk from `root`, emitting every visited node with its edge type on entry | Simple, teaches `visit` + `report` + typed reports cleanly; useful for external tooling |

All walkers use the typed `has reports: list[T] = []` channel so the returned
data is strongly typed on the client / CLI side.

### 4.3 When to Reach for Which

Rule of thumb: **start with `def:pub`; switch to a walker when either**

- the operation genuinely traverses multiple graph levels (e.g.
  `workspace_summary` recurses over the whole DAG),
- **or** the operation modifies the graph as it walks (`refresh_stale_analyses`),
- **or** it's an agent that makes decisions at each hop (`investigate by llm`).

Otherwise, a function is the honest form.

---

## 5. Frontend Surface

The `cl` UI is authored in the same source. Rough layout:

```
┌────────────────────────────────────────────────────────────────┐
│ Datasets   │  sales_2025.csv          [Upload]                 │
│  ▸ sales   ├────────────────────────────────────────────────────┤
│  ▸ latency │  Metric: revenue                                   │
│            │  ┌──────────────────────────────────────────────┐  │
│            │  │  ECharts time-series (with anomaly markers   │  │
│            │  │  + forecast band overlay)                    │  │
│            │  └──────────────────────────────────────────────┘  │
│            │  Perspective pivot [pivot by region/channel/day]   │
│            │  ┌──────────────────────────────────────────────┐  │
│            │  │  Virtualized 60fps pivot / filter grid       │  │
│            │  └──────────────────────────────────────────────┘  │
│            │  Runs                     [Detect] [Forecast]      │
│            │  #12 anomaly  ▸ narrated  ─ Insight (LLM prose)    │
│            │  #11 forecast ▸ narrated                           │
└────────────────────────────────────────────────────────────────┘
```

### 5.1 Key Panels

- **Chart panel** — `echarts-for-react`. Brushable timeline; anomaly runs
  overlay markers; forecast runs overlay a shaded confidence band.
- **Pivot panel** — `@finos/perspective`. The raw or aggregated dataframe is
  streamed in; analysts pivot/filter/group without a round-trip.
- **Runs panel** — history of `AnalysisRun` nodes for the selected metric,
  each expandable to its `Insight` if one exists.
- **Sidebar** — the user's datasets and metrics; drag to reorganize.

### 5.2 Reactivity

State lives in `has` fields on components. When a walker returns a new run, the
runs panel updates without manual cache invalidation.

---

## 6. Build Targets

The same source builds to four artifacts.

### 6.1 CLI

```bash
metrics ingest ./sales_2025.csv --name sales
metrics metric --dataset sales --name revenue \
        --expression 'gross_revenue - refunds' --time order_ts
metrics anomaly --metric revenue --window 90d --algorithm iforest
metrics forecast --metric revenue --horizon 30d --seasonality weekly
metrics narrate --run 12
```

`jac nacompile` produces a single native binary. No Python interpreter needed
on the user's machine.

### 6.2 Fullstack Web

```bash
jac start --client web
```

Multi-user analyst workbench. Per-user graph isolation is automatic; the
`root` under each authenticated session holds only that analyst's datasets.

### 6.3 Desktop

```bash
jac build --client desktop
jac start --client desktop
```

The same UI wrapped in an OS webview (WebKitGTK / WKWebView / WebView2). One
binary, no Electron. Positioned as the **airgapped analyst tool** — a
recognizable enterprise pain point.

### 6.4 Native Batch Runner

The CLI target above, but invoked non-interactively in CI:

```yaml
- run: metrics ingest s3://bucket/daily.csv --name daily
- run: metrics anomaly --metric orders --window 7d --json > report.json
```

Fast, no Python bootstrapping cost.

---

## 7. LLM Integration

Jac's `by llm` is used surgically, not as decoration. Two levels appear:

### 7.1 One-Shot `by llm` (Function Body)

- `def:pub narrate(run: AnalysisRun) -> Insight by llm` — given a run's
  structured output (anomalies, forecast points), the LLM writes a
  plain-English `Insight`.
  Example: *"Revenue dipped 12% on 2026-05-14, driven entirely by the EU
  region. This coincides with the Berlin CDN outage window; consider
  correlating with the SRE incident timeline."*

- `def:pub suggest_metric(ds: Dataset) -> list[MetricSuggestion] by llm` —
  UX affordance: given a dataset's column names and a sample, the LLM
  proposes candidate metrics and pandas expressions.

### 7.2 Agentic `by llm` (Walker Decision Ability)

- `walker investigate` uses `by llm` **inside each entry ability** to decide
  what to `visit` next. This is the OSP-with-AI headline story: nodes are
  states, edges are transitions, and the walker + `by llm` decides on the
  fly whether to hop to sibling metrics, dig into recent runs, or stop and
  narrate.

The workshop story: `by llm` replaces prompt-engineering boilerplate with a
typed function signature. The LLM's inputs and outputs are Jac types, not
strings — and inside a walker, the LLM becomes the agent's decision-making
brain over a structured state space.

---

## 8. Sample Data

Synthesised e-commerce operational time-series. Small enough to ship in the
repo, structured enough to produce interesting anomalies and forecasts.

Suggested columns:

| Column | Type | Notes |
|---|---|---|
| `order_ts` | timestamp | 1-minute granularity, ~90 days |
| `region` | enum | `NA`, `EU`, `APAC`, `LATAM` |
| `channel` | enum | `web`, `mobile`, `partner` |
| `orders` | int | volume |
| `gross_revenue` | float | currency, USD |
| `refunds` | float | currency, USD |
| `page_load_ms_p95` | float | latency percentile |
| `error_rate` | float | 0..1 |

Injected anomalies:

- A promo spike (revenue + orders both jump for 48h).
- A regional outage (EU orders drop to zero for 3h, `error_rate` spikes).
- A slow degradation (latency drifts upward over 2 weeks).

Each anomaly makes a specific workshop point about a specific package.

---

## 9. Non-Goals

Explicit boundaries to keep the scope honest for a workshop:

- **Not a BI tool.** No dashboard-builder UX, no SQL playground, no drilldowns
  beyond what Perspective gives for free.
- **Not a data warehouse.** DuckDB and parquet are optional; the reference
  path is CSV → in-memory pandas.
- **Not a scheduler.** Batch runs are triggered externally (CI, cron), not
  managed inside the app.
- **Not multi-tenant beyond per-user.** No org/workspace hierarchy; each
  authenticated user is their own workspace via `root`.
- **Not real-time streaming.** Datasets are ingested as bounded files, not
  Kafka topics. (Streaming could be a workshop-extension appendix.)

---

## 10. Open Questions

These need answers before implementation begins:

- **Storage backend for persistence** — SQLite (default), or MongoDB for the
  demo? See `run-modes` in the lake.
- **Auth provider** — what does the workshop demo use for the fullstack path?
- **LLM provider config** — `by llm` needs a configured model; do we assume
  OpenAI, Anthropic, or a local model for the workshop machines?
- **Sample dataset size** — how big do we go? Enough rows to make Perspective's
  virtualization impressive without shipping a 200MB file in the repo.
- **Module progression** — how do we sequence "build this app" across the
  workshop's time budget? (Next design step.)

---

## References

- Sirno lake (source of truth for Jac concepts):
  `~/Space/miorin/jaseci-lake/sirno-lake/`
- Relevant lake entries: `per-user-graph`, `fullstack-vs-traditional`,
  `desktop-app`, `batteries-included`, `by-llm`, `node`, `edge-keyword`,
  `graph-traversal-directions`, `api-generation`.
