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
    has threshold: float = 2.5;
    has count: int = 0;
    has anomalies: list[int] = [];
    has values: list[float] = [];
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
        m = sum(vals) / n;
        var = sum([(v - m) ** 2 for v in vals]) / n;
        std = var ** 0.5;
        idx: list[int] = [];
        flagged: list[float] = [];
        for (i, v) in enumerate(vals) {
            z = (v - m) / std if std > 0.0 else 0.0;
            if abs(z) > th {
                idx.append(i);
                flagged.append(v);
            }
        }
        run = Run(threshold=th, count=len(idx), anomalies=idx, values=flagged);
        s ++> run;
        report {"run": jid(run), "anomalies": len(idx), "indices": idx};
    }
}

# Interop showcase: a least-squares trend projection, with numpy doing the math
# inline. Same file as the pure-Jac scan above - no glue between the two.
walker:pub forecast {
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
        report {"slope": slope, "intercept": intercept, "horizon": h, "forecast": proj};
    }
}

# Hand the latest run's numbers to the LLM; store its prose as an Insight node.
walker:pub narrate {
    has series: str;

    can run with Root entry {
        smatches = [-->][?:Series, name == self.series];
        if not smatches {
            report {"error": f"no series named {self.series}"};
            disengage;
        }
        s = smatches[0];
        runs = [s -->][?:Run];
        if not runs {
            report {"error": "no runs yet - scan first"};
            disengage;
        }
        run = runs[-1];
        payload = write_insight(self.series, run.count, run.values);
        ins = Insight(summary=payload.summary, bullets=payload.bullets);
        run ++> ins;
        report {"summary": payload.summary, "bullets": payload.bullets};
    }
}
