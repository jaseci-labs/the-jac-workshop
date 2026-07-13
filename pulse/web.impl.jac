"""Implementations for the Pulse web dashboard.

Each method calls a server walker with `root spawn` and drops the result into
reactive state; `chart_data` shapes the series for recharts.
"""

impl app.do_auth -> None {
    authbusy = True;
    autherr = "";
    sr: dict | None = None;   # jacSignup returns a dict
    ok: bool = False;         # jacLogin returns a bool
    if authmode == "signup" {
        sr = await jacSignup(email, password);
        if not sr["success"] {
            autherr = "Sign-up failed (the email may already be in use)";
            authbusy = False;
            return;
        }
    }
    ok = await jacLogin(email, password);
    if not ok {
        autherr = "Invalid credentials";
        authbusy = False;
        return;
    }
    authed = True;
    authbusy = False;
    boot();   # first authenticated call — loads this user's own data
}

impl app.boot -> None {
    r = root spawn dashboard(series="orders");
    pts = r.reports[0]["points"];
    idx = r.reports[0]["anomalies"];
    points = pts;
    anomalies = idx;
    status = f"{len(pts)} points · {len(idx)} anomalies";
}

impl app.do_scan -> None {
    busy = True;
    status = "scanning…";
    r = root spawn dashboard(series="orders");
    pts = r.reports[0]["points"];
    idx = r.reports[0]["anomalies"];
    points = pts;
    anomalies = idx;
    status = f"{len(idx)} anomalies flagged";
    busy = False;
}

impl app.do_forecast -> None {
    busy = True;
    status = "forecasting…";
    r = root spawn forecast(series="orders", horizon=14);
    sl = r.reports[0]["slope"];
    ic = r.reports[0]["intercept"];
    slope = sl;
    intercept = ic;
    status = "forecast ready";
    busy = False;
}

impl app.do_narrate -> None {
    busy = True;
    status = "narrating…";
    r = root spawn narrate(series="orders");
    su = r.reports[0]["summary"];
    bu = r.reports[0]["bullets"];
    summary = su;
    bullets = bu;
    status = "insight ready";
    busy = False;
}

impl app.chart_data -> list {
    out = [];
    for (i, v) in enumerate(points) {
        row = {"i": i, "orders": v};
        if i in anomalies {
            row["anomaly"] = v;
        }
        if slope != 0.0 {
            row["trend"] = slope * i + intercept;
        }
        out.append(row);
    }
    return out;
}
