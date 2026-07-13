"""Pulse - full-stack entry point.

The SAME walkers from api.jac, now behind a browser UI. One command:

    jac start --dev main.jac       # → http://localhost:8000

Importing the walkers here registers them as REST endpoints; the `cl` block
mounts the client dashboard (web.cl.jac). No CORS, no fetch layer, no schema
duplicated as TypeScript - the client calls the walkers directly.
"""

import from api { seed, scan, forecast, narrate, series_points, dashboard, run_history }

cl {
    import from .web { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
