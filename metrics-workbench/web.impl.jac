"""Implementations for the Metrics Workbench dashboard.

Each method calls a server walker with `root spawn`; the walker runs pandas /
pyod / statsmodels and reports client-ready dicts.
"""

impl app.boot -> None {
    root spawn wb_seed();
    r = root spawn wb_dashboard(dataset="sales", metric="revenue");
    d = r.reports[0];
    ch = d["chart"];
    ac = d["anomaly_count"];
    pc = d["point_count"];
    av = d["aic"];
    chart = ch;
    anomaly_count = ac;
    point_count = pc;
    aic = av;
    status = f"{pc} daily points · {ac} anomalies · SARIMAX fit";
}

impl app.do_narrate -> None {
    busy = True;
    status = "detecting + narrating…";
    r = root spawn wb_narrate(dataset="sales", metric="revenue");
    d = r.reports[0];
    su = d["summary"];
    bu = d["bullets"];
    summary = su;
    bullets = bu;
    status = "insight ready";
    busy = False;
}

impl app.do_suggest -> None {
    busy = True;
    status = "asking the llm for metrics…";
    r = root spawn wb_suggest(dataset="sales");
    sg = r.reports[0];
    suggestions = sg;
    status = f"{len(sg)} metrics suggested";
    busy = False;
}
