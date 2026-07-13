"""Implementations for the Pulse web dashboard.

Each method calls a server walker with `root spawn` and drops the result into
reactive state. `.reports` holds the walker's `report` values (untyped dict
access here - the same shape the CLI prints).
"""

impl app.boot -> None {
    sp = root spawn series_points(series="orders");
    pts = sp.reports[0]["points"];
    if not pts {
        root spawn seed(name="orders", n=90);
        sp = root spawn series_points(series="orders");
        pts = sp.reports[0]["points"];
    }
    points = pts;
    sc = root spawn scan(series="orders");
    anomalies = sc.reports[0]["indices"];
    na = sc.reports[0]["anomalies"];
    status = f"{len(pts)} points · {na} anomalies";
}

impl app.do_scan -> None {
    status = "scanning…";
    r = root spawn scan(series="orders");
    anomalies = r.reports[0]["indices"];
    na = r.reports[0]["anomalies"];
    status = f"{na} anomalies flagged";
}

impl app.do_forecast -> None {
    status = "forecasting…";
    r = root spawn forecast(series="orders", horizon=14);
    sl = r.reports[0]["slope"];
    status = f"forecast trend: slope {sl}";
}

impl app.do_narrate -> None {
    status = "narrating…";
    r = root spawn narrate(series="orders");
    summary = r.reports[0]["summary"];
    bullets = r.reports[0]["bullets"];
    status = "insight ready";
}

impl app.chart_svg -> str {
    n = len(points);
    if n == 0 {
        return "<svg viewBox='0 0 620 230'></svg>";
    }
    # integer coords keep the SVG path clean (no ultra-long floats)
    d = "";
    for (i, v) in enumerate(points) {
        x = int(10.0 + i / 89.0 * 600.0);
        y = int(215.0 - float(str(v)) / 660.0 * 200.0);   # str()->float across the any boundary
        cmd = "M" if i == 0 else "L";
        d = d + cmd + str(x) + " " + str(y) + " ";
    }
    dots = "";
    for a in anomalies {
        ai = int(str(a));
        cx = int(10.0 + ai / 89.0 * 600.0);
        cy = int(215.0 - float(str(points[ai])) / 660.0 * 200.0);
        dots = dots + "<circle cx='" + str(cx) + "' cy='" + str(cy) + "' r='5' fill='#ff5470' stroke='#0b0e14' stroke-width='2'/>";
    }
    return "<svg viewBox='0 0 620 230' width='100%' height='auto'><path d='" + d + "' fill='none' stroke='#3a4658' stroke-width='2'/>" + dots + "</svg>";
}
