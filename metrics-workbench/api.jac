"""Metrics Workbench — slice 1: backend + CLI.

The graph model (Object-Spatial Programming), the walkers, and the CLI
entry point live here. The pandas/statsmodels/pyod numerics live in the
sibling analytics.py module — Python does what Python is good at.
"""

import from analytics {
    dataset_info_row_count as py_row_count,
    dataset_info_columns as py_columns,
    preview_metric as py_preview,
    detect_anomalies as py_detect,
    forecast as py_forecast,
    summarize_run_for_narration as py_summarize,
    output_anomaly_summary as py_anomaly_summary,
    output_forecast_summary as py_forecast_summary,
    output_field_int as py_output_int,
    json_dumps as py_dumps,
    to_json as py_json,
    web_dashboard as py_web_dashboard
}

import from datetime { datetime }
import sys;


# ---------------------------------------------------------------------------
# Structured payloads (LLM outputs, CLI-friendly return shapes)
# ---------------------------------------------------------------------------

obj MetricPoint {
    has ts: str, value: float;
}

obj InsightPayload {
    has summary: str;
    has bullets: list[str];
    has confidence: float;
}

obj MetricSuggestion {
    has name: str, expression: str, rationale: str;
}

obj RunSummary {
    has jid: str, kind: str, run_at: str, anomaly_count: int = 0, horizon_days: int = 0;
}

obj MetricSnapshot {
    has name: str, expression: str, run_count: int, latest_kind: str;
}

obj DatasetSnapshot {
    has name: str, row_count: int, metric_count: int, metrics: list[MetricSnapshot];
}

obj WorkspaceSnapshot {
    has dataset_count: int, datasets: list[DatasetSnapshot];
}

obj LineageEntry {
    has kind: str, name: str, jid: str;
}

enum Direction {
    LOOK_AT_RUNS,
    HOP_SIBLING,
    STOP_AND_NARRATE
}


# ---------------------------------------------------------------------------
# Graph model — nodes
# ---------------------------------------------------------------------------

node Dataset {
    has name: str;
    has source_path: str;
    has row_count: int = 0;
    has columns: list[str] = [];
    has ingested_at: str = "";
}

node Metric {
    has name: str;
    has expression: str;
    has time_column: str;
    has dtype: str = "float";
}

node AnalysisRun {
    has kind: str;             # "anomaly" | "forecast"
    has params_json: str = "{}";
    has window: str = "";
    has output_json: str = "{}";
    has duration_ms: int = 0;
    has run_at: str = "";
}

node Insight {
    has summary: str = "";
    has bullets: list[str] = [];
    has confidence: float = 0.0;
    has authored_by: str = "";
    has authored_at: str = "";
}


# ---------------------------------------------------------------------------
# Graph model — typed edges (endpoints declared so traversals infer types)
# ---------------------------------------------------------------------------

edge Derives: Dataset --> Metric {
    has expression: str;
    has time_column: str;
}

edge AnalyzedBy: Metric --> AnalysisRun {
    has kind: str;
    has run_at: str;
}

edge NarratedBy: AnalysisRun --> Insight {
    has model: str;
    has authored_at: str;
}


# ---------------------------------------------------------------------------
# LLM-backed functions
# ---------------------------------------------------------------------------

# One-shot narration: LLM writes a short structured commentary from a run's
# summarised findings. The signature IS the prompt.
def narrate(kind: str, metric_name: str, findings_json: str) -> InsightPayload by llm();

# Suggest candidate metrics for a dataset given its columns and a data sample.
def suggest_metrics(dataset_name: str, columns_json: str, sample_json: str) -> list[MetricSuggestion] by llm();

# Agentic decision inside `walker investigate`: given the analyst's question,
# the current metric, and a summary of recent runs, decide where to walk next.
def decide_next(question: str, current_metric: str, recent_runs_summary: str) -> Direction by llm();


# ---------------------------------------------------------------------------
# Lookup helpers (flat CRUD — reach into the graph, return a value)
# ---------------------------------------------------------------------------

def:pub list_datasets() -> list[Dataset] {
    return [root-->][?:Dataset];
}

def find_dataset(target_name: str) -> Dataset {
    matches = [root-->][?:Dataset, name == target_name];
    if not matches {
        raise ValueError(f"no dataset named {target_name}");
    }
    return matches[0];
}

def find_metric(dataset_name: str, target_metric: str) -> Metric {
    ds = find_dataset(dataset_name);
    matches = [ds ->:Derives:->][?:Metric, name == target_metric];
    if not matches {
        raise ValueError(f"no metric named {target_metric} on {dataset_name}");
    }
    return matches[0];
}

def find_run(dataset_name: str, metric_name: str, jid_prefix: str) -> AnalysisRun {
    m = find_metric(dataset_name, metric_name);
    runs = [m ->:AnalyzedBy:->];
    for r in runs {
        if jid(r).startswith(jid_prefix) {
            return r;
        }
    }
    raise ValueError(f"no run with jid prefix {jid_prefix}");
}


# ---------------------------------------------------------------------------
# def:pub — the flat CRUD API (functions, not walkers)
# ---------------------------------------------------------------------------

def:pub ingest_dataset(name: str, path: str) -> Dataset {
    ds = root ++> Dataset(
        name=name,
        source_path=path,
        row_count=py_row_count(path),
        columns=py_columns(path),
        ingested_at=datetime.now().isoformat()
    );
    return ds;
}

def:pub define_metric(dataset_name: str, name: str, expression: str, time_column: str) -> Metric {
    ds = find_dataset(dataset_name);
    m = Metric(name=name, expression=expression, time_column=time_column);
    ds +>: Derives(expression=expression, time_column=time_column) :+> m;
    return m;
}

def:pub preview_metric(dataset_name: str, metric_name: str, n: int = 10) -> list[MetricPoint] {
    ds = find_dataset(dataset_name);
    m = find_metric(dataset_name, metric_name);
    rows = py_preview(ds.source_path, m.expression, m.time_column, n);
    out: list[MetricPoint] = [];
    for r in rows {
        out.append(MetricPoint(ts=str(r["ts"]), value=float(str(r["value"]))));
    }
    return out;
}

def:pub detect_anomalies(dataset_name: str, metric_name: str, window_days: int = 90, algorithm: str = "iforest") -> AnalysisRun {
    ds = find_dataset(dataset_name);
    m = find_metric(dataset_name, metric_name);
    started = datetime.now();
    output = py_detect(ds.source_path, m.expression, m.time_column, window_days, algorithm);
    elapsed = int((datetime.now() - started).total_seconds() * 1000);
    now_iso = datetime.now().isoformat();
    run = AnalysisRun(
        kind="anomaly",
        params_json=py_dumps({"algorithm": algorithm, "window_days": window_days}),
        window=f"{window_days}d",
        output_json=py_dumps(output),
        duration_ms=elapsed,
        run_at=now_iso
    );
    m +>: AnalyzedBy(kind="anomaly", run_at=now_iso) :+> run;
    return run;
}

def:pub forecast(dataset_name: str, metric_name: str, horizon_days: int = 30, seasonality: str = "weekly") -> AnalysisRun {
    ds = find_dataset(dataset_name);
    m = find_metric(dataset_name, metric_name);
    started = datetime.now();
    output = py_forecast(ds.source_path, m.expression, m.time_column, horizon_days, seasonality);
    elapsed = int((datetime.now() - started).total_seconds() * 1000);
    now_iso = datetime.now().isoformat();
    run = AnalysisRun(
        kind="forecast",
        params_json=py_dumps({"horizon_days": horizon_days, "seasonality": seasonality}),
        window=f"{horizon_days}d",
        output_json=py_dumps(output),
        duration_ms=elapsed,
        run_at=now_iso
    );
    m +>: AnalyzedBy(kind="forecast", run_at=now_iso) :+> run;
    return run;
}

def:pub list_runs(dataset_name: str, metric_name: str) -> list[RunSummary] {
    m = find_metric(dataset_name, metric_name);
    runs = [m ->:AnalyzedBy:->];
    result: list[RunSummary] = [];
    for r in runs {
        result.append(RunSummary(
            jid=jid(r),
            kind=r.kind,
            run_at=r.run_at,
            anomaly_count=py_output_int(r.output_json, "anomaly_count"),
            horizon_days=py_output_int(r.output_json, "horizon_days")
        ));
    }
    return result;
}

def:pub narrate_run(dataset_name: str, metric_name: str, run_jid_prefix: str) -> Insight {
    run = find_run(dataset_name, metric_name, run_jid_prefix);
    findings = py_summarize(run.kind, run.output_json);
    payload = narrate(run.kind, metric_name, findings);
    now_iso = datetime.now().isoformat();
    insight = Insight(
        summary=payload.summary,
        bullets=payload.bullets,
        confidence=payload.confidence,
        authored_by="by-llm",
        authored_at=now_iso
    );
    run +>: NarratedBy(model="by-llm", authored_at=now_iso) :+> insight;
    return insight;
}

def:pub delete_dataset(name: str) -> str {
    ds = find_dataset(name);
    # Cascade: metrics → their runs → their insights.
    for m in [ds ->:Derives:->] {
        for r in [m ->:AnalyzedBy:->] {
            for i in [r ->:NarratedBy:->] {
                del i;
            }
            del r;
        }
        del m;
    }
    del ds;
    return f"deleted {name}";
}


# ---------------------------------------------------------------------------
# Walkers — OSP traversal that earns its keep
# ---------------------------------------------------------------------------

# 1. workspace_summary — nested recursion via `visit [-->]`. Reports one
#    WorkspaceSnapshot after visiting every Dataset, Metric, and AnalysisRun
#    in the graph.
walker workspace_summary {
    has snapshots: list[DatasetSnapshot] = [];
    has stack: list[DatasetSnapshot] = [];
    has reports: list[WorkspaceSnapshot] = [];

    can start with Root entry {
        visit [-->];
    }

    can enter_ds with Dataset entry {
        self.stack.append(DatasetSnapshot(
            name=here.name,
            row_count=here.row_count,
            metric_count=0,
            metrics=[]
        ));
        visit [here ->:Derives:->];
    }

    can leave_ds with Dataset exit {
        snap = self.stack.pop();
        self.snapshots.append(snap);
    }

    can at_metric with Metric entry {
        latest_kind = "";
        runs = [here ->:AnalyzedBy:->];
        if runs {
            latest_kind = runs[-1].kind;
        }
        if self.stack {
            ds = self.stack[-1];
            ds.metrics.append(MetricSnapshot(
                name=here.name,
                expression=here.expression,
                run_count=len(runs),
                latest_kind=latest_kind
            ));
            ds.metric_count += 1;
        }
    }

    can done with Root exit {
        report WorkspaceSnapshot(
            dataset_count=len(self.snapshots),
            datasets=self.snapshots
        );
    }
}

# 2. refresh_stale_analyses — walker that MODIFIES the graph as it moves.
#    Visits every Metric; if the newest AnalysisRun is older than
#    max_age_days (or none exists), spawns a fresh anomaly detection and
#    attaches the new run node.
walker refresh_stale_analyses {
    has max_age_days: int = 7;
    has refreshed: list[str] = [];
    has reports: list[list[str]] = [];

    can start with Root entry {
        visit [-->];
    }

    can hop with Dataset entry {
        visit [here ->:Derives:->];
    }

    can maybe_refresh with Metric entry {
        runs = [here ->:AnalyzedBy:->];
        stale = False;
        if not runs {
            stale = True;
        } else {
            latest = runs[-1];
            latest_at = datetime.fromisoformat(latest.run_at);
            age_days = (datetime.now() - latest_at).days;
            if age_days > self.max_age_days {
                stale = True;
            }
        }
        if stale {
            parents = [here <-:Derives:<-];
            if parents {
                ds = parents[0];
                now_iso = datetime.now().isoformat();
                output = py_detect(ds.source_path, here.expression, here.time_column, 90, "iforest");
                run = AnalysisRun(
                    kind="anomaly",
                    params_json=py_dumps({"algorithm": "iforest", "window_days": 90, "refresh": True}),
                    window="90d",
                    output_json=py_dumps(output),
                    duration_ms=0,
                    run_at=now_iso
                );
                here +>: AnalyzedBy(kind="anomaly", run_at=now_iso) :+> run;
                self.refreshed.append(here.name);
            }
        }
    }

    can done with Root exit {
        report self.refreshed;
    }
}

# 3. prune_orphan_insights — traversal that DELETES as it walks. An Insight
#    is "orphan" if its parent AnalysisRun no longer exists (edge dangling).
#    Uses `disengage` to stop early on the healthy path.
walker prune_orphan_insights {
    has deleted: list[str] = [];
    has reports: list[list[str]] = [];

    can start with Root entry {
        visit [-->];
    }

    can descend with Dataset | Metric | AnalysisRun entry {
        visit [-->];
    }

    can check with Insight entry {
        parents = [here <-:NarratedBy:<-];
        if parents {
            disengage;
        }
        self.deleted.append(jid(here));
        del here;
    }

    can done with Root exit {
        report self.deleted;
    }
}

# 4. export_lineage — flat DAG dump. Emits every visited node as a LineageEntry.
walker export_lineage {
    has entries: list[LineageEntry] = [];
    has reports: list[list[LineageEntry]] = [];

    can start with Root entry {
        visit [-->];
    }

    can at_ds with Dataset entry {
        self.entries.append(LineageEntry(kind="Dataset", name=here.name, jid=jid(here)));
        visit [-->];
    }

    can at_metric with Metric entry {
        self.entries.append(LineageEntry(kind="Metric", name=here.name, jid=jid(here)));
        visit [-->];
    }

    can at_run with AnalysisRun entry {
        self.entries.append(LineageEntry(kind="AnalysisRun", name=here.kind, jid=jid(here)));
        visit [-->];
    }

    can at_insight with Insight entry {
        self.entries.append(LineageEntry(kind="Insight", name=here.summary[:40], jid=jid(here)));
    }

    can done with Root exit {
        report self.entries;
    }
}

# 5. investigate — agentic walker. `by llm` decides where to hop at each
#    Metric visited. This is the OSP-with-AI pattern.
walker investigate {
    has question: str;
    has max_hops: int = 5;
    has trail: list[str] = [];
    has reports: list[InsightPayload] = [];

    can begin with Root entry {
        datasets = [-->][?:Dataset];
        if not datasets {
            report InsightPayload(
                summary="No datasets ingested yet.",
                bullets=[],
                confidence=0.0
            );
            disengage;
        }
        metrics = [datasets[0] ->:Derives:->];
        if metrics {
            visit metrics;
        }
    }

    can at_metric with Metric entry {
        self.trail.append(here.name);
        if len(self.trail) > self.max_hops {
            self._finalize(here.name, "hop budget exhausted");
            disengage;
        }
        recent = [here ->:AnalyzedBy:->];
        kinds_str = ",".join([r.kind for r in recent]);
        recent_summary = f"{len(recent)} runs; kinds=[{kinds_str}]";
        decision = decide_next(self.question, here.name, recent_summary);
        hopped = False;
        if decision == Direction.LOOK_AT_RUNS and recent {
            visit [recent[-1]];
            hopped = True;
        } elif decision == Direction.HOP_SIBLING {
            parents = [here <-:Derives:<-];
            if parents {
                siblings = [parents[0] ->:Derives:->];
                fresh: list[Metric] = [];
                for s in siblings {
                    if s.name not in self.trail {
                        fresh.append(s);
                    }
                }
                if fresh {
                    visit [fresh[0]];
                    hopped = True;
                }
            }
        }
        if not hopped {
            self._finalize(here.name, recent_summary);
            disengage;
        }
    }

    can at_run with AnalysisRun entry {
        findings = py_summarize(here.kind, here.output_json);
        payload = narrate(here.kind, "investigation", findings);
        report payload;
        disengage;
    }

    def _finalize(metric_name: str, findings: str) {
        payload = narrate("investigation", metric_name, findings);
        report payload;
    }
}


# ---------------------------------------------------------------------------
# Web-facing walkers — called from the client dashboard via `root spawn`.
# `:protect` means JWT-authenticated + per-user: each caller runs on their OWN
# root, so their Dataset/Metric/AnalysisRun/Insight graph is theirs alone
# (only `:pub` skips auth; `:protect` also keeps them importable by the client).
# They reuse the def:pub functions + analytics above, and report client-ready
# dicts (the same shape the CLI prints).
# ---------------------------------------------------------------------------

walker:protect wb_seed {
    can run with Root entry {
        existing = [-->][?:Dataset, name == "sales"];
        if not existing {
            ingest_dataset("sales", "data/synth_ecom.csv");
            define_metric("sales", "revenue", "gross_revenue - refunds", "order_ts");
        }
        report {"seeded": True};
    }
}

walker:protect wb_dashboard {
    has dataset: str = "sales";
    has metric: str = "revenue";
    can run with Root entry {
        ds = find_dataset(self.dataset);
        m = find_metric(self.dataset, self.metric);
        report py_web_dashboard(ds.source_path, m.expression, m.time_column, 90, 30, "weekly");
    }
}

walker:protect wb_narrate {
    has dataset: str = "sales";
    has metric: str = "revenue";
    can run with Root entry {
        run = detect_anomalies(self.dataset, self.metric, 90, "iforest");
        insight = narrate_run(self.dataset, self.metric, jid(run)[:8]);
        report {
            "summary": insight.summary,
            "bullets": insight.bullets,
            "confidence": insight.confidence
        };
    }
}

walker:protect wb_suggest {
    has dataset: str = "sales";
    can run with Root entry {
        ds = find_dataset(self.dataset);
        sample = py_preview(ds.source_path, "orders", "order_ts", 3);
        suggestions = suggest_metrics(ds.name, py_dumps(ds.columns), py_dumps(sample));
        out: list[dict] = [];
        for s in suggestions {
            out.append({"name": s.name, "expression": s.expression, "rationale": s.rationale});
        }
        report out;
    }
}

walker:protect wb_runs {
    has dataset: str = "sales";
    has metric: str = "revenue";
    can run with Root entry {
        out: list[dict] = [];
        for r in list_runs(self.dataset, self.metric) {
            out.append({"jid": r.jid[:8], "kind": r.kind, "run_at": r.run_at, "anomalies": r.anomaly_count, "horizon": r.horizon_days});
        }
        report out;
    }
}


# ---------------------------------------------------------------------------
# CLI dispatch
# ---------------------------------------------------------------------------

def cli_help() {
    print("metrics-workbench — Jac workshop demo");
    print("");
    print("Commands:");
    print("  ingest <name> <path>                       Ingest a CSV/parquet");
    print("  datasets                                   List ingested datasets");
    print("  metric <dataset> <name> <expr> <time-col>  Define a metric");
    print("  preview <dataset> <metric> [n]             Preview a metric's daily series");
    print("  anomaly <dataset> <metric> [window-days]   Run anomaly detection");
    print("  forecast <dataset> <metric> [horizon-days] Run a forecast");
    print("  runs <dataset> <metric>                    List runs on a metric");
    print("  narrate <dataset> <metric> <run-jid>       Ask the LLM to narrate a run");
    print("  delete <dataset>                           Delete a dataset (cascades)");
    print("");
    print("OSP walkers:");
    print("  summary                                    Workspace snapshot (traverses all)");
    print("  refresh [max-age-days]                     Refresh stale anomaly runs in place");
    print("  prune                                      Delete orphan insights");
    print("  lineage                                    Dump the DAG");
    print("  investigate <question>                     Agentic walker (by llm decisions)");
}

with entry:__main__ {
    if len(sys.argv) < 2 {
        cli_help();
    } else {
        cmd = sys.argv[1];
        args = sys.argv[2:];
        if cmd == "help" or cmd == "-h" or cmd == "--help" {
            cli_help();
        } elif cmd == "ingest" {
            ds = ingest_dataset(args[0], args[1]);
            print(py_json({"name": ds.name, "rows": ds.row_count, "columns": ds.columns}));
        } elif cmd == "datasets" {
            for d in list_datasets() {
                print(f"{d.name}\t{d.row_count} rows\t{d.source_path}");
            }
        } elif cmd == "metric" {
            m = define_metric(args[0], args[1], args[2], args[3]);
            print(f"defined metric {m.name} on {args[0]}: {m.expression}");
        } elif cmd == "preview" {
            n = int(args[2]) if len(args) > 2 else 10;
            points = preview_metric(args[0], args[1], n);
            for p in points {
                print(f"{p.ts}\t{p.value:.2f}");
            }
        } elif cmd == "anomaly" {
            window = int(args[2]) if len(args) > 2 else 90;
            arun = detect_anomalies(args[0], args[1], window, "iforest");
            print(f"run {jid(arun)[:8]}  {py_anomaly_summary(arun.output_json)}  {arun.duration_ms}ms");
        } elif cmd == "forecast" {
            horizon = int(args[2]) if len(args) > 2 else 30;
            frun = forecast(args[0], args[1], horizon, "weekly");
            print(f"run {jid(frun)[:8]}  {py_forecast_summary(frun.output_json)}  {frun.duration_ms}ms");
        } elif cmd == "runs" {
            for r in list_runs(args[0], args[1]) {
                print(f"{r.jid[:8]}\t{r.kind}\t{r.run_at}\tanomalies={r.anomaly_count}\thorizon={r.horizon_days}");
            }
        } elif cmd == "narrate" {
            insight = narrate_run(args[0], args[1], args[2]);
            print(insight.summary);
            for b in insight.bullets {
                print(f"  - {b}");
            }
            print(f"(confidence={insight.confidence:.2f})");
        } elif cmd == "delete" {
            print(delete_dataset(args[0]));
        } elif cmd == "summary" {
            summary_res = root spawn workspace_summary();
            snap = summary_res.reports[0];
            print(f"workspace: {snap.dataset_count} datasets");
            for d in snap.datasets {
                print(f"  {d.name}  ({d.row_count} rows, {d.metric_count} metrics)");
                for m in d.metrics {
                    print(f"    - {m.name}  runs={m.run_count}  latest={m.latest_kind}");
                }
            }
        } elif cmd == "refresh" {
            max_age = int(args[0]) if args else 7;
            refresh_res = root spawn refresh_stale_analyses(max_age_days=max_age);
            refreshed = refresh_res.reports[0] if refresh_res.reports else [];
            print(f"refreshed {len(refreshed)} metric(s): {refreshed}");
        } elif cmd == "prune" {
            prune_res = root spawn prune_orphan_insights();
            deleted = prune_res.reports[0] if prune_res.reports else [];
            print(f"pruned {len(deleted)} orphan insight(s)");
        } elif cmd == "lineage" {
            lineage_res = root spawn export_lineage();
            entries = lineage_res.reports[0] if lineage_res.reports else [];
            for e in entries {
                print(f"{e.kind}\t{e.name}\t{e.jid[:8]}");
            }
        } elif cmd == "investigate" {
            question = " ".join(args);
            investigate_res = root spawn investigate(question=question);
            for p in investigate_res.reports {
                print(p.summary);
                for b in p.bullets {
                    print(f"  - {b}");
                }
                print("---");
            }
        } else {
            print(f"unknown command: {cmd}");
            cli_help();
        }
    }
}
