"""Pulse - full-stack entry point.

The SAME walkers from api.jac, now behind a browser UI. One command:

    jac run --dev main.jac         # → http://localhost:8000

The `:pub` / `:protect` walkers in api.jac are served as REST endpoints; `app`
mounts the client dashboard (web.jac - its JSX makes it client code, no marker
needed). No CORS, no fetch layer, no schema
duplicated as TypeScript - the client calls the walkers directly.
"""

import from api { seed, scan, forecast, narrate, series_points, dashboard, run_history }

import from .web { app as ClientApp }

def:pub app -> JsxElement {
    return <ClientApp/>;
}
