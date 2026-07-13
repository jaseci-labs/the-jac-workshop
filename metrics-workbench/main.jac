"""Metrics Workbench — full-stack entry point.

The SAME walkers from api.jac (backed by pandas / pyod / statsmodels in
analytics.py), now behind a browser dashboard. One command:

    jac start --dev main.jac       # → http://localhost:8000

Importing the walkers here registers them as REST endpoints; the `cl` block
mounts the client dashboard (web.cl.jac).
"""

import from api { wb_seed, wb_dashboard, wb_narrate, wb_suggest, wb_runs }

cl {
    import from .web { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
