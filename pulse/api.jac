"""Pulse - slim metric-anomaly narrator.

Pure Jac: the graph model, the z-score anomaly scan, and the LLM narration
all live here. No Python module, no pandas - Jac does the whole job.

The heavy Python-interop story (pyod / statsmodels) lives in the sibling
`metrics-workbench` capstone. Pulse is the slim live-build that fans out to
every build target with a near-zero diff:

    jac enter src/main.jac seed            # CLI subcommand (batteries-included)
    jac enter src/main.jac scan --series orders
    jac start src/main.jac                 # every walker -> POST /walker/<Name>
"""

# Python interop, the first-class way: import a library DIRECTLY into this .jac
# file and use it inline - one line, same file, no service, no glue. Here it is
# the stdlib `statistics` (ships everywhere); declaring a third-party lib like
# `pandas`/`numpy` in jac.toml is the *identical* one-line change. (Importing a
# separate analytics.py, like the capstone does, is the *other* thing - an
# escape hatch for code already written in Python.)
import from statistics { linear_regression }
import from datetime { datetime }

# ---------------------------------------------------------------------------
# Structured payload the LLM returns (typed in, typed out - not a string)
# ---------------------------------------------------------------------------
obj InsightText {
    has summary: str;
    has bullets: list[str];
}

# ---------------------------------------------------------------------------
# Graph model:  root --> Series --> Run --> Insight
# Anything hung off root auto-persists, per-user, with no DB code.
# ---------------------------------------------------------------------------
node Series {
    has name: str;
    has unit: str = "";
    has points: list[float] = [];
}

node Run {
    has kind: str = "scan";        # "scan" | "narrate" - what the user did
    has threshold: float = 2.5;
    has count: int = 0;
    has anomalies: list[int] = [];
    has values: list[float] = [];
    has run_at: str = "";          # readable timestamp, for the history panel
}

node Insight {
    has summary: str = "";
    has bullets: list[str] = [];
}

# ---------------------------------------------------------------------------
# AI as a language primitive: the signature IS the prompt. Inputs and the
# returned InsightText are Jac types, not strings we template and re-parse.
# The model is configured in jac.toml ([plugins.byllm.model]).
# ---------------------------------------------------------------------------
def write_insight(series_name: str, anomaly_count: int, flagged_values: list[float]) -> InsightText by llm();

# The z-score detector, in ONE place (pure Jac - no pandas, no pyod). `scan`
# (CLI), `dashboard` (web display) and `narrate` all share it, so the detection
# logic lives once. `_`-prefixed, so it stays a helper and never hits the API.
# Returns the flagged indices and their values.
def _detect(points: list[float], threshold: float) -> tuple[list[int], list[float]] {
    n = len(points);
    if n == 0 {
        return ([], []);
    }
    m = sum(points) / n;
    std = (sum([(v - m) ** 2 for v in points]) / n) ** 0.5;
    idx: list[int] = [];
    flagged: list[float] = [];
    for (i, v) in enumerate(points) {
        z = (v - m) / std if std > 0.0 else 0.0;
        if abs(z) > threshold {
            idx.append(i);
            flagged.append(v);
        }
    }
    return (idx, flagged);
}

# A readable timestamp for run history. `datetime` is a Python stdlib module
# imported straight into Jac - the same interop move as `statistics` above.
def _now() -> str {
    return datetime.now().strftime("%b %d · %H:%M:%S");
}

# ---------------------------------------------------------------------------
# Walkers - one surface, every target:
#   * CLI subcommand   -> jac enter src/main.jac scan --series orders
#   * REST endpoint    -> POST /walker/scan   (via :pub, per-user root)
#   * frontend RPC     -> root() spawn scan(series="orders")
# ---------------------------------------------------------------------------

# Generate a synthetic series in pure Jac so the demo needs no data file.
# A gentle upward trend with a 3-day promo spike and a 1-day outage dip -
# both land well outside 2.5 sigma, so `scan` has something to find.
walker:pub seed {
    has name: str = "orders";
    has n: int = 90;

    can run with Root entry {
        vals: list[float] = [];
        # coerce: `jac enter` hands CLI args in as strings (int() is a no-op
        # on the REST/spawn path where the body is already typed).
        for i in range(int(self.n)) {
            base = 200.0 + float(i);
            if i >= 30 and i < 33 {
                base = base + 400.0;
            }
            if i == 55 {
                base = 20.0;
            }
            vals.append(base);
        }
        s = Series(name=self.name, points=vals);
        root ++> s;
        report {"name": self.name, "points": len(vals)};
    }
}

walker:pub list_series {
    can run with Root entry {
        out: list[dict] = [];
        for s in [-->][?:Series] {
            out.append({"name": s.name, "points": len(s.points)});
        }
        report out;
    }
}

# Return a series' raw points (used by the web client to draw the chart).
walker:pub series_points {
    has series: str;
    can run with Root entry {
        matches = [-->][?:Series, name == self.series];
        if not matches {
            report {"points": []};
            disengage;
        }
        report {"points": matches[0].points};
    }
}

# Seed-if-empty + display: returns the series points and its current anomalies
# for the chart. Read-only - it does NOT record a Run (that's what `scan` and
# `narrate` do), so the history panel only reflects what the user explicitly ran.
# `:protect` = JWT-authenticated + per-user: it seeds and reads the CALLER's
# OWN root, so each signed-in user gets their own private series.
walker:protect dashboard {
    has series: str = "orders";
    can run with Root entry {
        matches = [-->][?:Series, name == self.series];
        if not matches {
            vals: list[float] = [];
            for i in range(90) {
                base = 200.0 + float(i);
                if i >= 30 and i < 33 {
                    base = base + 400.0;
                }
                if i == 55 {
                    base = 20.0;
                }
                vals.append(base);
            }
            s = Series(name=self.series, points=vals);
            root ++> s;
        } else {
            s = matches[0];
        }
        det = _detect(s.points, 2.5);
        report {"points": s.points, "anomalies": det[0]};
    }
}

# z-score anomaly detection, written in plain Jac (no pandas, no pyod).
walker:pub scan {
    has series: str;
    has threshold: float = 2.5;

    can run with Root entry {
        matches = [-->][?:Series, name == self.series];
        if not matches {
            report {"error": f"no series named {self.series}"};
            disengage;
        }
        s = matches[0];
        vals = s.points;
        n = len(vals);
        if n == 0 {
            report {"error": "series has no points"};
            disengage;
        }
        th = float(self.threshold);  # CLI args arrive as strings; coerce once.
        det = _detect(vals, th);     # the shared z-score detector
        idx = det[0];
        run = Run(kind="scan", threshold=th, count=len(idx), anomalies=idx, values=det[1], run_at=_now());
        s ++> run;
        report {"run": jid(run), "anomalies": len(idx), "indices": idx};
    }
}

# Interop showcase: a least-squares trend projection, with numpy doing the math
# inline. Same file as the pure-Jac scan above - no glue between the two.
walker:protect forecast {
    has series: str;
    has horizon: int = 14;

    can run with Root entry {
        matches = [-->][?:Series, name == self.series];
        if not matches {
            report {"error": f"no series named {self.series}"};
            disengage;
        }
        s = matches[0];
        vals = s.points;
        n = len(vals);
        if n < 2 {
            report {"error": "need at least 2 points to fit a trend"};
            disengage;
        }
        fit = linear_regression(range(n), vals);   # imported stdlib, used inline
        slope = float(str(fit.slope));              # str()->float across the boundary
        intercept = float(str(fit.intercept));
        h = int(self.horizon);
        proj = [slope * (n + k) + intercept for k in range(h)];
        # round for display (client JS has no Python format specs)
        report {"slope": round(slope, 3), "intercept": round(intercept, 2), "horizon": h, "forecast": proj};
    }
}

# Self-sufficient, like the capstone's wb_narrate: detect the anomalies, record
# the Run, then hand its numbers to the LLM and store the prose as an Insight.
# So Narrate works straight after boot, with no separate Scan first.
walker:protect narrate {
    has series: str;

    can run with Root entry {
        smatches = [-->][?:Series, name == self.series];
        if not smatches {
            report {"error": f"no series named {self.series}"};
            disengage;
        }
        s = smatches[0];
        det = _detect(s.points, 2.5);
        run = Run(kind="narrate", threshold=2.5, count=len(det[0]), anomalies=det[0], values=det[1], run_at=_now());
        s ++> run;
        payload = write_insight(self.series, run.count, run.values);
        ins = Insight(summary=payload.summary, bullets=payload.bullets);
        run ++> ins;
        report {"summary": payload.summary, "bullets": payload.bullets};
    }
}

# History: the user's recent runs on this series (newest first), each with its
# anomaly count and - if it was narrated - the LLM insight summary. The
# persistence payoff made visible: runs live on your own root, so they're still
# here next time you sign in (and another user sees only their own).
walker:protect run_history {
    has series: str = "orders";

    can run with Root entry {
        smatches = [-->][?:Series, name == self.series];
        if not smatches {
            report {"runs": []};
            disengage;
        }
        s = smatches[0];
        rns: list[Run] = [s -->][?:Run];        # typed, so the report schema resolves
        out: list[dict] = [];
        for r in rns {
            ins_list: list[Insight] = [r -->][?:Insight];
            summary = ins_list[-1].summary if ins_list else "";
            out.append({"kind": r.kind, "run_at": r.run_at, "anomalies": r.count, "summary": summary});
        }
        out.reverse();                    # newest first
        report {"runs": out[:8]};         # keep the panel tidy
    }
}
