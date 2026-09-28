"""Metrics Workbench — full-stack entry point.

The SAME walkers from api.jac (backed by pandas / pyod / statsmodels in
analytics.py), now behind a browser dashboard. One command:

    jac run --dev main.jac         # → http://localhost:8000

The `:protect` walkers in api.jac are served as REST endpoints; `app` mounts
the client dashboard (web.jac - its JSX makes it client code, no marker
needed).
"""

import from api { wb_seed, wb_dashboard, wb_narrate, wb_suggest, wb_runs }

import from .web { app as ClientApp }

def:pub app -> JsxElement {
    return <ClientApp/>;
}
