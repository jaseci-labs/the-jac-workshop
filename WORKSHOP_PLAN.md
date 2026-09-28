# Jac Workshop — "One Source, Every Target"

**Format:** 60–90 min, live-coded, follow-along.
**Audience:** working developers (Python / JS / REST fluent), enterprise-leaning.
**Goal:** not a sales pitch — a *demonstration* that Jac does things the rest of
the stack can't: AI as a typed language primitive, persistence + per-user
isolation as a runtime property, seamless Python/JS interop when you want it,
and **one source that compiles to every build target with a near-zero diff.**

---

## Status — what's built

> **Toolchain:** migrated to and re-verified on **jac 0.37.23** (Sep 2026):
> CLI, REST + auth, browser UI, wheel, PWA and desktop builds all re-run.
> 0.37 retired `jac enter` / `jac start` / `jac bundle` / `--client`, the
> `cl`/`sv` markers and the `.cl.jac` suffix — the commands below are the
> current spellings.

| Piece | State |
|---|---|
| `pulse/` — the slim **live-build** (Jac-first) | ✅ **built & verified running** — CLI `seed → scan → forecast → narrate` + full-stack web |
| **Full-stack web target** | ✅ **built, runs, screenshotted** — `jac run --dev main.jac` → dashboard + real LLM Insight |
| Live walkthrough site (GitHub Pages) | ✅ **published** → https://jaseci-labs.github.io/the-jac-workshop/ |
| `metrics-workbench/` — the **capstone** (heavy-lib showcase) | ✅ present (merged from `main`); backend + CLI + agentic AI |
| Package target | ✅ **built & verified** — `jac build --as wheel` → wheel; `pip install` + `import pulse` works (runtime vendored) |
| Installable app (PWA) | ✅ **built** — `[client.pwa]` in `jac.toml` + `jac build --as client` → manifest + service worker + install banner |
| Native desktop (macOS) | ✅ **builds** on 0.37.23 — `kind = "desktop"` + `jac build` → `.jac/client/desktop/pulse.app` (WKWebView, no manual `libwebview` step any more) |
| Web UI polish | ✅ **recharts + lucide-react** (npm) — real chart, stat cards, working Scan/Forecast/Narrate |

**Verified end-to-end (via `jac run --no-serve --entry`):**
- `scan` — the z-score, written in **pure Jac**, flagged `indices [30, 31, 32, 55]`:
  exactly the injected promo spike + outage dip.
- `forecast` — a `statistics.linear_regression` **imported inline into the `.jac`
  file** (`slope: 0.69 …`). That's the interop pillar — import a Python lib
  *directly into Jac*, use it in the same file, no glue — proven live.

(See §5.1 for the CLI facts this surfaced, incl. a bug running caught that
compiling did not.)

---

## 0. The single idea

Open on this screen (the "I like to build…" menu):

```
I like to build…
  ▸ CLI tools & native binaries
  ▸ Backend APIs & services
  ▸ Full-stack web apps
  ▸ Desktop & mobile apps
  ▸ AI agents & LLM apps
  ▸ Reusable libraries & packages
```

> "Every framework makes you pick one of these and marry it. We're going to
> write **one** small program, then walk down this whole list — and you'll watch
> the diff to each target be a flag or a file, not a rewrite."

That promise is the whole workshop. Everything below exists to make the
target-to-target diff **visibly tiny and live**. If the audience remembers one
thing, it's the scoreboard in §9.

---

## 1. Two apps, one story

We ship **two** apps on purpose — they make different points:

- **`pulse/` — the live-build.** A slim metric-anomaly narrator. Jac does the
  real work itself (the z-score `scan` is pure Jac), and where a library helps,
  it's imported **directly into the `.jac` file and used inline** (`forecast`
  uses `statistics.linear_regression`) — Python interop, first-class, no glue,
  no separate module. Small enough that the core fits on one screen. This is
  what we build live.
- **`metrics-workbench/` — the capstone.** The deep version (SARIMAX forecasts,
  `pyod` anomaly ensembles, OSP walkers). It leans on heavy libs (`pandas`,
  `statsmodels`, `pyod`) kept in a separate `analytics.py` — the *escape-hatch*
  flavor of interop, for teams who already have Python code. We don't build it
  live; we point at it as "here's how deep it goes."

**On "Python interop" (the precise claim):** it means `import from <lib>` **inside
a `.jac` file**, used inline in the same file — one import, no service, no glue.
The capstone's separate `analytics.py` is the *other* thing: an escape hatch for
existing Python, not the headline. Pulse shows the headline version live.

This split cleanly separates the claims:

| Claim | Where it's proven |
|---|---|
| Native DB + per-user isolation, AI as a primitive, one-source-every-target | **Pulse** (live) |
| Python interop — import any lib **inline into a `.jac` file**, no glue | **Pulse `forecast`** (live) + capstone (heavy libs) |

### Pulse's graph (3 nodes)

```
root ──▶ Series ──▶ Run ──▶ Insight
```

- **`Series`** — a metric column. Fields: `name`, `unit`, `points[]`.
- **`Run`** — one z-score scan. Fields: `threshold`, `count`, `anomalies[]`, `values[]`.
- **`Insight`** — the LLM narrative. Fields: `summary`, `bullets[]`.

Everything hangs off `root`, so it auto-persists, per-user, with **no DB code**.

### Pulse's walkers (the entire surface)

Every walker is *simultaneously* a CLI subcommand, a REST endpoint (`:pub`), and
a frontend RPC — the one-surface thesis, literally.

| Walker | Does | Proves |
|---|---|---|
| `seed(name, n)` | generates a synthetic series **in Jac** (trend + injected spike + dip) | zero data-file dependency |
| `scan(series, threshold)` | z-score over the series **in Jac** → `Run` | you don't even need Python for this |
| `forecast(series, horizon)` | least-squares trend via `statistics.linear_regression` **imported inline** | **Python interop, first-class** (one import, same file) |
| `narrate(series)` | LLM writes an `Insight` from the latest run's numbers | **AI as a primitive** (typed, not prompt-strings) |
| `list_series()` | enumerate the user's series | **native DB** (per-user, free) |

~155 lines of core. Every target below imports it **unchanged**. Note `scan`
(pure Jac) and `forecast` (imported lib) sit in the **same file, no glue** —
that side-by-side *is* the interop point.

---

## 2. Decisions locked (so we don't stall live)

| Question | Choice | Why |
|---|---|---|
| Storage backend | **Embedded Postgres** (default, zero-config) | `jac run` provisions it and gives each user a persistent root; point `JAC_DB_URL` at a managed Postgres to scale. |
| Auth | **Built-in JWT** (`:protect` walkers) | `:protect` = per-user isolation with zero code; no external IdP. |
| LLM provider | **`claude-sonnet-4-20250514` (matches capstone), MockLLM as the offline safety net** | Demo must survive dead wifi / no keys. Set in `pulse/jac.toml`. |
| Sample data | **Generated in Jac by `seed`** — no CSV shipped | Zero file dependency; deterministic; the injected spike+dip are always found. |

> **Wire MockLLM as the default and flip to live Claude for one "wow" moment.**
> If the network dies mid-session, `narrate` still returns prose and nobody
> notices. (Exact MockLLM config is the one remaining to-do — see §12.)

---

## 3. What each target proves (scoreboard preview)

| Target | The diff to get there | Differentiator |
|---|---|---|
| CLI + native binary | **0 lines** — `jac run --entry <walker> …`; `jac build --native` for the binary | ships without a Python runtime |
| Backend API | **already there** — `:pub` walkers are per-user REST endpoints | native DB + auth, no FastAPI/ORM |
| Full-stack web | **1 file** — one `web.jac` page + a plain `import` of the walkers | no CORS, no fetch glue, no TS schema dupes |
| Desktop / mobile | **1 config line** — `kind = "desktop"`; a phone gets the PWA (`[client.pwa]`) | no Electron, no rewrite |
| AI agent | **~small** — expose walkers as agent tools (capstone already has `investigate`) | the app *is* the toolset |
| Reusable package | **config** — `jac build --as wheel` / `--as npm` | ship the core to others |

---

## 4. Run of show — 90 min

| Time | Segment | Beat |
|---|---|---|
| 0:00–0:08 | **The promise** | Show the menu (§0). One source, walk the whole list. |
| 0:08–0:26 | **Build Pulse core** | Live-author the 3 nodes + 5 walkers. Four moments: `root`-scoped graph (**native DB**); z-score in **pure Jac** ("Jac stands alone"); `forecast` = `import from statistics` used **inline** ("**interop**: any Python lib, same file, no glue"); `narrate by llm` (**AI primitive**). Run `seed → scan → forecast`. |
| 0:26–0:33 | **Target 1 — CLI + binary** | Same walkers, now `jac run --entry` entrypoints. `jac build --native` → a binary with no Python on the box. |
| 0:33–0:45 | **Target 2 — Backend API** | Swap `:pub` → `:protect`. `jac run`. `curl POST /walker/scan`. Register two users → their graphs are **invisible to each other** with zero code. The enterprise-credibility beat — give it air. |
| 0:45–0:58 | **Target 3 — Full-stack web** | One `web.jac` page: recharts chart (**JS interop**) + Scan/Narrate buttons via `root() spawn`. No fetch, no CORS. Click Narrate → same walker, now in a browser. |
| 0:58–1:06 | **Target 4 — Desktop / mobile** | `kind = "desktop"` + `jac build`. Same UI in an OS webview. Mention the PWA for phones. |
| 1:06–1:16 | **Target 5 — App as an AI agent** | Expose walkers as tools an LLM calls. **Show the capstone's `investigate` walker** — an agentic `by llm` traversal that already exists. |
| 1:16–1:22 | **Target 6 — Reusable package** | `jac build --as wheel`. The core becomes `pip`/`npm` installable. |
| 1:22–1:30 | **Scoreboard + the capstone** | §9. Then: "and when you need pandas/statsmodels — here's the capstone, same patterns, one source." Q&A. |

**60-min cut:** core → CLI/binary → Backend API → Full-stack web → scoreboard.
Demote Desktop, Agent, Package to a 90-second "flag montage." See §11.

---

## 5. The core (real, validated code)

Lives in [pulse/api.jac](pulse/api.jac). Compiles clean; runs. The
three teaching moments live here and **never change again** — every target in
§6 is a shell around this file.

```jac
node Series  { has name: str; has unit: str = ""; has points: list[float] = []; }
node Run     { has threshold: float = 2.5; has count: int = 0;
               has anomalies: list[int] = []; has values: list[float] = []; }
node Insight { has summary: str = ""; has bullets: list[str] = []; }

# AI is a typed function, not a prompt string:
obj InsightText { has summary: str; has bullets: list[str]; }
def write_insight(series_name: str, anomaly_count: int,
                  flagged_values: list[float]) -> InsightText by llm();

# z-score in plain Jac — no pandas, no pyod:
walker:pub scan {
    has series: str;
    has threshold: float = 2.5;
    can run with Root entry {
        s = [-->][?:Series, name == self.series][0];
        vals = s.points;
        m = sum(vals) / len(vals);
        std = (sum([(v - m) ** 2 for v in vals]) / len(vals)) ** 0.5;
        th = float(self.threshold);        # CLI args arrive as strings — coerce
        idx = [i for (i, v) in enumerate(vals) if abs((v - m) / std) > th];
        run = Run(threshold=th, count=len(idx), anomalies=idx);
        s ++> run;
        report {"run": jid(run), "anomalies": len(idx), "indices": idx};
    }
}
```

### 5.1 What running it taught us (bake into the talk track)

- **`jac run --no-serve --entry <walker> <file> <args…>` is the free CLI** — zero
  code (`--no-serve` because Pulse is a `web-app`, so bare `jac run` serves). But args
  are **positional and arrive as strings**: `scan orders 3.0`, *not*
  `scan --series orders --threshold 3.0`. Numeric fields must be coerced in the
  walker (`float(self.threshold)`) — which the core now does. (Pretty `--flag`
  UX or a `pulse scan` binary is a small `with entry:__main__` dispatcher, like
  the capstone has — that's the "+ a few lines" upgrade, not the free tier.)
- The scan is **stateful across CLI calls** — `seed` then `scan` in separate
  invocations Just Works because the graph persists to `root`. That *is* the
  native-DB story, visible from the CLI with no server.
- **Interop is a one-line import, verified live** — `forecast` does
  `import from statistics { linear_regression }` at the top of `main.jac` and
  calls it inline. A third-party lib is the identical line + a
  `[dependencies.pip]` entry. **Caveat found on this box:** its Jac runs Python
  **3.14**, which had no prebuilt `numpy` wheel (and `jac run --entry` uses the runtime
  env, not the project venv), so the demo ships the stdlib lib. On a 3.11/3.12
  workshop image, `pandas`/`numpy` is the same one-liner — **confirm the machine's
  Python before promising a specific lib on stage.**
- **Cross the untyped-lib boundary with `float(str(x))`** — an imported lib's
  results are `Unknown` to the type-checker, so `float(lib_val)` errors;
  `float(str(lib_val))` passes and runs. (The capstone uses the same trick.)

---

## 6. Each target = a diff (the heart of the workshop)

Show these as literal `git diff`-style reveals. The point is the smallness.

### 6.1 CLI + native binary — *diff: 0 lines*
```bash
jac run --no-serve --entry seed main.jac               # → {'name': 'orders', 'points': 90}
jac run --no-serve --entry scan main.jac orders        # → {'anomalies': 4, 'indices': [30, 31, 32, 55]}
jac run --no-serve --entry forecast main.jac orders 14 # → linear_regression imported inline (interop)
jac run --no-serve --entry narrate main.jac orders
jac build --native tool.jac                            # → single native binary, no Python needed
```
> Native caveat (checked on 0.37.23): Pulse itself can't go native — its
> `statistics`/`datetime` interop is outside the native subset. Demo the binary
> with a small pure-Jac file, not `api.jac`.
**Beat:** "This runs in CI on a box with no Python installed."

### 6.2 Backend API — *already there (`:protect` for per-user)*
The walkers are already `:pub`. Start the server:
```bash
jac run --dev main.jac
curl -X POST .../walker/scan -d '{"series":"orders"}'
```
Every `:pub`/`:protect` walker is a REST endpoint (verified: `POST /walker/scan`
→ `200`). Switch `:pub`→`:protect` and register two users → **each sees only their own `Series`**.
No auth-scoping code, no `WHERE user_id`, no ORM. **This is the slide enterprise
architects photograph.**

### 6.3 Full-stack web — *diff: 1 file · ✅ BUILT*
Add one page ([pulse/web.jac](pulse/web.jac)) that imports
the walkers and calls `scan` / `forecast` / `narrate` via `root spawn`. No
`fetch`, no CORS, no Pydantic-model-retyped-as-a-TS-interface. UI state is
reactive `has` fields; the chart is SVG built from the same data the CLI prints.
```bash
jac run --dev main.jac           # → http://localhost:8000
```
**Verified running** — screenshot in the walkthrough. Click **Narrate** and the
browser calls the same `narrate` walker → Claude writes a typed `Insight` → the
card renders it. One walker, two front doors.

> Layout note: the fullstack build wants flat root modules — walkers live in
> `api.jac`, the entry+mount in `main.jac`, the client in `web.jac` /
> `web.impl.jac` (client placement is inferred from its JSX — no `cl` marker). Jac JSX has no SVG intrinsics, so the chart is built as an SVG
> string and injected with `dangerouslySetInnerHTML`.

### 6.4 Desktop / mobile — *diff: 1 config line*
```toml
# jac.toml
[project]
kind = "desktop"                # then `jac build` → OS webview app, no Electron, no Rust

[client.pwa]                    # web-app kind: installable on phones + desktops
theme_color = "#ff6a3d"         # then `jac setup && jac build --as client`
```
(A native phone app is now a separate `kind = "mobile"` React Native/mobUI app —
Capacitor is gone in 0.37 — so for this workshop the phone story is the PWA.)

### 6.5 App as an AI agent — *already demonstrated in the capstone*
`metrics-workbench`'s `investigate` walker uses `by llm` (`decide_next`) to
choose where to hop through the graph — an agentic traversal. Show it; the app
you built **is** the agent's toolset.

### 6.6 Reusable package — *diff: config*
```bash
jac build --as npm          # component library
jac build --as wheel        # pip-installable CLI / importable core
```

---

## 7. AI shows up twice (say this explicitly)

Don't let AI look like a stage-6 bolt-on. Two distinct forms:

1. **AI *inside* the app** — `narrate by llm` lives in the **core**, so every
   target inherits it for free. AI is a property of the source.
2. **The app *as* an agent** — §6.5 — walkers become an LLM's tools (the
   capstone's `investigate` already does this).

Same primitive, two directions.

---

## 8. The differentiators, stated plainly

Each is *shown*, not asserted:

- **AI as a language primitive.** `by llm` is a typed function signature.
  Inputs and outputs are Jac types, not strings you template and re-parse.
- **Native DB + per-user isolation.** Your data model *is* your persistence *is*
  your API. `root` + `:protect` = per-user isolation, zero code. No ORM, no
  migration table, no auth filter. (Visible even from the CLI — §5.1.)
- **Python interop with no glue.** `import from <lib>` **inside a `.jac` file**,
  used inline in the same file — one import, no service, no wrapper, no
  microservice. Pulse's `forecast` does it live (`statistics.linear_regression`);
  swap in `pandas`/`numpy` with the same line. *Not* "call a Python microservice
  from Node." (A separate `analytics.py`, like the capstone's, is the escape
  hatch for existing Python — a side capability, not the headline.)
- **One source → every target.** The scoreboard. The diffs are flags and files.

---

## 9. Closing scoreboard

```
                          Pulse core:  ~155 lines  (Jac + one inline import)
  ────────────────────────────────────────────────────────────
  CLI + native binary ......... + 0 lines    (jac run --entry <walker>)
  Backend REST API ............ already there (:pub → per-user endpoints)
  Full-stack web app .......... + 1 file      (web.jac page)
  Desktop app ................. + 1 line      (kind = "desktop")
  Installable / phone (PWA) ... + 1 table     ([client.pwa])
  AI agent .................... walkers as tools (capstone: investigate)
  Reusable package ............ + config
  ────────────────────────────────────────────────────────────
  Six targets off the menu. One core. No rewrites.
  Inside that core: pure-Jac scan + an imported lib (forecast), same file,
  no glue — and the capstone scales the same interop to pandas/statsmodels.
```

Close: *"You didn't pick a lane. You wrote the program, and Jac gave you the
whole menu."*

---

## 10. Presenter prep (before the room)

- [ ] `pulse/` core is written & verified — for the live segment, retype only
      the three teaching moments; the rest is on screen.
- [ ] Run `jac clean` and clear the persisted graph before starting, so `seed`
      begins from an empty root (the demo builds up state live).
- [ ] `MockLLM` wired as default in `pulse/jac.toml`; live Claude key exported
      for the one live-narrate moment. Test both paths offline.
- [ ] Native binary **pre-built** as a fallback if `nacompile` is slow on stage
      hardware — but run it live if time allows.
- [ ] Each target on its own git branch/tag so a `git diff` shows the reveal.
- [ ] Desktop build pre-compiled (build times are the enemy of live demos).
- [ ] Two demo users pre-registered to show isolation instantly.
- [ ] Confirm every command verb against the installed Jac version the day of.

**Failure fallbacks:** wifi dies → MockLLM covers it. Build hangs → pre-built
artifact on disk. Runs long → drop to the 60-min cut mid-stream (§11).

---

## 11. The 60-minute cut

| Time | Segment |
|---|---|
| 0:00–0:06 | The promise (§0) |
| 0:06–0:22 | Build Pulse core (§1) |
| 0:22–0:29 | CLI + native binary (§6.1) |
| 0:29–0:41 | Backend API + per-user isolation (§6.2) — keep this full |
| 0:41–0:53 | Full-stack web (§6.3) |
| 0:53–0:57 | Desktop/mobile/agent/package as a 90-sec "flag montage" |
| 0:57–1:00 | Scoreboard (§9) + point at the capstone |

The montage still *shows* the flags so the "every target" claim stays honest —
you're just not building them live.

---

## 12. Remaining to-do (before the workshop is turnkey)

- ✅ **Web target** — `web.jac` dashboard, built, running, screenshotted.
- ✅ **Walkthrough site** — published to GitHub Pages, auto-deploys on push.
- ✅ **narrate verified** — real Claude Haiku 4.5 output (CLI + browser).
- ✅ **Package target** — `jac build --as wheel` → wheel + sdist; verified `pip install` +
  `import pulse` in a clean venv (jac runtime vendored into the wheel).
- ✅ **Installable app (PWA)** — `[client.pwa]` (with at least one key — an
  empty table is ignored) + `jac setup && jac build --as client` builds manifest
  + service worker + install banner (works on this macOS box).
- ✅ **Native desktop** — `kind = "desktop"` + `jac build` builds a macOS
  `pulse.app` (WKWebView) on 0.37.23; the old GTK-only `build_libwebview.sh`
  step is gone.
- ⬜ **Per-target git branches** — one tag per target so `git diff` is the reveal.

---

## 13. Deliberately out of scope (for the 60–90 min)

- No forecasting (SARIMAX/Prophet) or Perspective pivot grid in the live build —
  that's the capstone.
- No dashboard-builder UX, no SQL playground.
- No multi-tenant hierarchy beyond per-user `root`.
- No streaming/Kafka.
