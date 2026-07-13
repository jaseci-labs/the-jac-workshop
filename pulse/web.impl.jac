"""Implementations for the Pulse web dashboard.

Each method calls a server walker with `root spawn` and drops the result into
reactive state; `chart_data` shapes the series for recharts.
"""

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
