"""Pulse - client dashboard (compiled from Jac to React).

`sv import` pulls the server walkers in as typed client calls; `root spawn`
invokes them over the wire with no fetch/CORS glue. The chart is `recharts`
(an npm package, imported directly), icons are `lucide-react`.
"""

import from "recharts" { ResponsiveContainer, ComposedChart, Line, Scatter, XAxis, YAxis, CartesianGrid, Tooltip }
import from "lucide-react" { Activity, Search, TrendingUp, Sparkles, TriangleAlert, LogOut, History, Clock }
import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }

sv import from api { dashboard, scan, forecast, narrate, run_history }

glob CSS = """
  .pulse-btn{display:inline-flex;align-items:center;gap:8px;padding:10px 16px;border-radius:10px;font-weight:600;font-size:.9rem;cursor:pointer;border:1px solid #2b3444;background:#161c28;color:#e6edf3;transition:transform .12s ease,background .12s ease,border-color .12s ease;}
  .pulse-btn:hover{transform:translateY(-1px);background:#1b2331;border-color:#3a475b;}
  .pulse-btn:disabled{opacity:.5;cursor:default;transform:none;}
  .pulse-btn.primary{background:linear-gradient(100deg,#ff6a3d,#ff8a52);border-color:transparent;color:#1a0d08;}
  .pulse-btn.primary:hover{filter:brightness(1.05);}
  .stat{background:#121620;border:1px solid #232a36;border-radius:14px;padding:16px 18px;flex:1;transition:border-color .15s;}
  .stat:hover{border-color:#33405a;}
  .stat .v{font-size:1.7rem;font-weight:700;letter-spacing:-.02em;line-height:1;}
  .stat .l{font-size:.72rem;text-transform:uppercase;letter-spacing:.09em;color:#5d6b80;margin-top:7px;font-family:ui-monospace,monospace;}
  .pulse-in{width:100%;padding:11px 13px;border-radius:10px;border:1px solid #2b3444;background:#0c0f16;color:#e6edf3;font-size:.95rem;outline:none;transition:border-color .15s;}
  .pulse-in:focus{border-color:#ff6a3d;}
  .lnk{color:#ff6a3d;cursor:pointer;font-weight:600;}
""";

def:pub app -> JsxElement {
    has authed: bool = jacIsLoggedIn(),
        email: str = "",
        password: str = "",
        authmode: str = "login",
        autherr: str = "",
        authbusy: bool = False,
        points: list = [],
        anomalies: list = [],
        slope: float = 0.0,
        intercept: float = 0.0,
        summary: str = "",
        bullets: list = [],
        history: list[dict] = [],
        status: str = "loading…",
        busy: bool = False;

    can with entry {
        if authed {
            boot();
        }
    }

    async def do_auth -> None;
    async def boot -> None;
    async def do_scan -> None;
    async def do_forecast -> None;
    async def do_narrate -> None;
    def chart_data -> list;

    # ---- unauthenticated: login / sign-up gate ----
    if not authed {
        return
            <div style={{
                "minHeight": "100vh", "display": "grid", "placeItems": "center",
                "background": "radial-gradient(120% 90% at 50% -10%, #131a26 0%, #0b0e14 55%)",
                "color": "#e6edf3", "fontFamily": "system-ui, -apple-system, Segoe UI, sans-serif"
            }}>
                <style>{CSS}</style>
                <div style={{"width": "360px", "maxWidth": "90vw", "background": "#11151d", "border": "1px solid #232a36", "borderRadius": "16px", "padding": "28px 26px"}}>
                    <div style={{"display": "flex", "alignItems": "center", "gap": "11px", "marginBottom": "6px"}}>
                        <div style={{"width": "38px", "height": "38px", "borderRadius": "11px", "display": "grid", "placeItems": "center", "background": "linear-gradient(135deg, rgba(255,106,61,.28), rgba(43,212,196,.14))", "border": "1px solid #2b3444"}}><Activity size={20} color="#ff6a3d"/></div>
                        <div style={{"fontSize": "1.25rem", "fontWeight": "700"}}>Pulse</div>
                    </div>
                    <p style={{"color": "#93a0b4", "fontSize": ".88rem", "margin": "0 0 20px"}}>
                        {"Sign in — your series live on your own graph." if authmode == "login" else "Create an account — you get your own isolated workspace."}
                    </p>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "11px"}}>
                        <input className="pulse-in" type="email" placeholder="email" value={email}
                            onChange={lambda e: ChangeEvent { email = e.target.value; }}/>
                        <input className="pulse-in" type="password" placeholder="password" value={password}
                            onChange={lambda e: ChangeEvent { password = e.target.value; }}
                            onKeyDown={lambda e: KeyboardEvent { if e.key == "Enter" { do_auth(); } }}/>
                        {autherr and <div style={{"color": "#ff5470", "fontSize": ".84rem"}}>{autherr}</div>}
                        <button className="pulse-btn primary" disabled={authbusy} style={{"justifyContent": "center", "marginTop": "4px"}} onClick={lambda { do_auth(); }}>
                            {"…" if authbusy else ("Sign in" if authmode == "login" else "Create account")}
                        </button>
                    </div>
                    <div style={{"marginTop": "16px", "fontSize": ".86rem", "color": "#93a0b4", "textAlign": "center"}}>
                        {(authmode == "login") and <span>No account? <span className="lnk" onClick={lambda { authmode = "signup"; autherr = ""; }}>Create one</span></span>}
                        {(authmode == "signup") and <span>Have an account? <span className="lnk" onClick={lambda { authmode = "login"; autherr = ""; }}>Sign in</span></span>}
                    </div>
                </div>
            </div>;
    }

    # ---- authenticated: the dashboard (runs on this user's own root) ----
    return
        <div style={{
            "minHeight": "100vh", "background": "radial-gradient(120% 90% at 50% -10%, #131a26 0%, #0b0e14 55%)",
            "color": "#e6edf3", "fontFamily": "system-ui, -apple-system, Segoe UI, sans-serif"
        }}>
            <style>{CSS}</style>
            <div style={{"maxWidth": "980px", "margin": "0 auto", "padding": "40px 22px 60px"}}>

                <div style={{"display": "flex", "alignItems": "center", "gap": "13px"}}>
                    <div style={{
                        "width": "42px", "height": "42px", "borderRadius": "12px", "display": "grid", "placeItems": "center",
                        "background": "linear-gradient(135deg, rgba(255,106,61,.25), rgba(43,212,196,.18))",
                        "border": "1px solid #2b3444"
                    }}><Activity size={22} color="#ff6a3d"/></div>
                    <div style={{"flex": "1"}}>
                        <div style={{"fontSize": "1.5rem", "fontWeight": "700", "letterSpacing": "-.02em", "lineHeight": "1"}}>Pulse</div>
                        <div style={{"color": "#8b95a5", "fontSize": ".9rem", "marginTop": "3px"}}>
                            Anomaly detection &amp; forecasting — the same Jac walkers as the CLI, in your browser.
                        </div>
                    </div>
                    <button className="pulse-btn" onClick={lambda { jacLogout(); authed = False; }} style={{"padding": "8px 12px"}}><LogOut size={15}/> Sign out</button>
                </div>

                <div style={{"display": "flex", "gap": "14px", "marginTop": "26px"}}>
                    <div className="stat"><div className="v">{len(points)}</div><div className="l">data points</div></div>
                    <div className="stat"><div className="v" style={{"color": "#ff5470"}}>{len(anomalies)}</div><div className="l">anomalies</div></div>
                    <div className="stat"><div className="v" style={{"color": "#2bd4c4"}}>{slope if slope != 0.0 else "—"}</div><div className="l">forecast slope / day</div></div>
                </div>

                <div style={{
                    "background": "#0f1420", "border": "1px solid #232a36", "borderRadius": "16px",
                    "padding": "18px 14px 10px", "marginTop": "16px"
                }}>
                    <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "padding": "0 8px 10px"}}>
                        <div style={{"fontWeight": "600", "fontSize": ".95rem"}}>orders</div>
                        <div style={{"display": "flex", "gap": "16px", "fontSize": ".75rem", "color": "#8b95a5", "fontFamily": "ui-monospace,monospace"}}>
                            <span><span style={{"color": "#5b8bd4"}}>—</span> series</span>
                            <span><span style={{"color": "#ff5470"}}>●</span> anomaly</span>
                            <span><span style={{"color": "#2bd4c4"}}>--</span> forecast</span>
                        </div>
                    </div>
                    <ResponsiveContainer width="100%" height={330}>
                        <ComposedChart data={chart_data()} margin={{"top": 6, "right": 14, "left": -12, "bottom": 0}}>
                            <CartesianGrid strokeDasharray="3 3" stroke="#1e2634" vertical={False}/>
                            <XAxis dataKey="i" stroke="#4a5872" fontSize={11} tickLine={False} axisLine={False} minTickGap={28}/>
                            <YAxis stroke="#4a5872" fontSize={11} tickLine={False} axisLine={False} width={44}/>
                            <Tooltip contentStyle={{"background": "#121620", "border": "1px solid #2b3444", "borderRadius": "10px", "color": "#e6edf3", "fontSize": ".82rem"}} labelStyle={{"color": "#8b95a5"}} cursor={{"stroke": "#33405a"}}/>
                            <Line type="monotone" dataKey="orders" stroke="#5b8bd4" strokeWidth={2} dot={False} isAnimationActive={True}/>
                            <Line type="monotone" dataKey="trend" stroke="#2bd4c4" strokeWidth={2} strokeDasharray="6 5" dot={False} connectNulls={True} isAnimationActive={False}/>
                            <Scatter dataKey="anomaly" fill="#ff5470" line={False}/>
                        </ComposedChart>
                    </ResponsiveContainer>
                </div>

                <div style={{"display": "flex", "gap": "11px", "marginTop": "18px", "alignItems": "center", "flexWrap": "wrap"}}>
                    <button className="pulse-btn" disabled={busy} onClick={lambda { do_scan(); }}><Search size={16}/> Scan</button>
                    <button className="pulse-btn" disabled={busy} onClick={lambda { do_forecast(); }}><TrendingUp size={16}/> Forecast</button>
                    <button className="pulse-btn primary" disabled={busy} onClick={lambda { do_narrate(); }}><Sparkles size={16}/> Narrate</button>
                    <span style={{"color": "#5d6b80", "fontSize": ".85rem", "fontFamily": "ui-monospace,monospace", "marginLeft": "4px"}}>{status}</span>
                </div>

                {summary and
                    <div style={{
                        "marginTop": "20px", "padding": "20px 22px", "borderRadius": "16px",
                        "background": "linear-gradient(160deg, rgba(255,106,61,.10), #10131c)",
                        "border": "1px solid rgba(255,106,61,.28)"
                    }}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "8px", "color": "#ff8a52", "fontSize": ".78rem", "fontFamily": "ui-monospace,monospace", "marginBottom": "10px"}}>
                            <Sparkles size={15}/> INSIGHT · authored by llm
                        </div>
                        <div style={{"fontWeight": "600", "fontSize": "1.02rem", "lineHeight": "1.5"}}>{summary}</div>
                        <div style={{"marginTop": "12px", "display": "flex", "flexDirection": "column", "gap": "7px"}}>
                            {[<div key={idx} style={{"display": "flex", "gap": "9px", "color": "#a7b0c0", "fontSize": ".92rem"}}>
                                <TriangleAlert size={15} color="#ff6a3d" style={{"flexShrink": "0", "marginTop": "3px"}}/>
                                <span>{b}</span>
                            </div> for (idx, b) in enumerate(bullets)]}
                        </div>
                    </div>
                }

                {history and
                    <div style={{
                        "marginTop": "18px", "background": "#0f1420", "border": "1px solid #232a36",
                        "borderRadius": "16px", "padding": "16px 18px"
                    }}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "8px", "color": "#8b95a5", "fontSize": ".76rem", "fontFamily": "ui-monospace,monospace", "letterSpacing": ".05em", "marginBottom": "12px"}}>
                            <History size={15}/> RECENT RUNS · persisted on your root — still here when you sign back in
                        </div>
                        <div style={{"display": "flex", "flexDirection": "column", "gap": "8px"}}>
                            {[<div key={idx} style={{"display": "flex", "alignItems": "center", "gap": "11px", "padding": "9px 12px", "borderRadius": "10px", "background": "#121620", "border": "1px solid #1e2634"}}>
                                <span style={{
                                    "fontSize": ".68rem", "fontWeight": "700", "padding": "2px 9px", "borderRadius": "20px", "fontFamily": "ui-monospace,monospace",
                                    "background": "rgba(255,106,61,.16)" if r["kind"] == "narrate" else "rgba(91,139,212,.16)",
                                    "color": "#ff8a52" if r["kind"] == "narrate" else "#5b8bd4"
                                }}>{r["kind"]}</span>
                                <Clock size={13} color="#5d6b80"/>
                                <span style={{"color": "#8b95a5", "fontSize": ".82rem", "fontFamily": "ui-monospace,monospace", "whiteSpace": "nowrap"}}>{r["run_at"]}</span>
                                <span style={{"color": "#e6edf3", "fontSize": ".85rem", "whiteSpace": "nowrap"}}>{r["anomalies"]} anomalies</span>
                                {r["summary"] and <span style={{"color": "#5d6b80", "fontSize": ".82rem", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>— {r["summary"]}</span>}
                            </div> for (idx, r) in enumerate(history)]}
                        </div>
                    </div>
                }
            </div>
        </div>;
}
