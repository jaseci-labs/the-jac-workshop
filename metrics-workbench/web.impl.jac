"""Implementations for the Metrics Workbench dashboard.

Each method calls a server walker with `root spawn`; the walker runs pandas /
pyod / statsmodels and reports client-ready dicts.
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
    hr = root spawn wb_runs(dataset="sales", metric="revenue");   # this user's own past runs
    history = hr.reports[0];
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
    hr = root spawn wb_runs(dataset="sales", metric="revenue");   # the detect run now shows in history
    history = hr.reports[0];
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
