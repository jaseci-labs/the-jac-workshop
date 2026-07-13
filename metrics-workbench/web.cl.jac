"""Metrics Workbench — client dashboard (compiled from Jac to React).

`sv import` pulls the server walkers in as typed client calls; `root spawn`
invokes them over HTTP. The numbers behind the chart come from pandas /
pyod / statsmodels running server-side (analytics.py). The chart is
`recharts`; icons are `lucide-react`.
"""

import from "recharts" { ResponsiveContainer, ComposedChart, Line, Scatter, Area, XAxis, YAxis, CartesianGrid, Tooltip }
import from "lucide-react" { Database, TriangleAlert, Sparkles, Lightbulb, ScanSearch }

sv import from api { wb_seed, wb_dashboard, wb_narrate, wb_suggest }

glob CSS = """
  .mw-btn{display:inline-flex;align-items:center;gap:8px;padding:10px 16px;border-radius:10px;font-weight:600;font-size:.9rem;cursor:pointer;border:1px solid #2b3444;background:#161c28;color:#e6edf3;transition:transform .12s ease,background .12s ease,border-color .12s ease;}
  .mw-btn:hover{transform:translateY(-1px);background:#1b2331;border-color:#3a475b;}
  .mw-btn:disabled{opacity:.5;cursor:default;transform:none;}
  .mw-btn.primary{background:linear-gradient(100deg,#7c5cff,#9d7bff);border-color:transparent;color:#0d0a1a;}
  .stat{background:#121620;border:1px solid #232a36;border-radius:14px;padding:16px 18px;flex:1;transition:border-color .15s;}
  .stat:hover{border-color:#33405a;}
  .stat .v{font-size:1.7rem;font-weight:700;letter-spacing:-.02em;line-height:1;}
  .stat .l{font-size:.72rem;text-transform:uppercase;letter-spacing:.09em;color:#5d6b80;margin-top:7px;font-family:ui-monospace,monospace;}
  .card{background:#10141d;border:1px solid #232a36;border-radius:16px;padding:20px 22px;margin-top:18px;}
""";

def:pub app -> JsxElement {
    has chart: list = [],
        anomaly_count: int = 0,
        point_count: int = 0,
        aic: float = 0.0,
        summary: str = "",
        bullets: list = [],
        suggestions: list = [],
        status: str = "loading…",
        busy: bool = False;

    can with entry {
        boot();
    }

    async def boot -> None;
    async def do_narrate -> None;
    async def do_suggest -> None;

    return
        <div style={{
            "minHeight": "100vh", "background": "radial-gradient(120% 90% at 50% -10%, #16131f 0%, #0b0d13 55%)",
            "color": "#e6edf3", "fontFamily": "system-ui, -apple-system, Segoe UI, sans-serif"
        }}>
            <style>{CSS}</style>
            <div style={{"maxWidth": "1020px", "margin": "0 auto", "padding": "40px 22px 64px"}}>

                <div style={{"display": "flex", "alignItems": "center", "gap": "13px"}}>
                    <div style={{
                        "width": "44px", "height": "44px", "borderRadius": "12px", "display": "grid", "placeItems": "center",
                        "background": "linear-gradient(135deg, rgba(124,92,255,.28), rgba(43,212,196,.16))", "border": "1px solid #2b3444"
                    }}><Database size={22} color="#9d7bff"/></div>
                    <div>
                        <div style={{"fontSize": "1.5rem", "fontWeight": "700", "letterSpacing": "-.02em", "lineHeight": "1"}}>Metrics Workbench</div>
                        <div style={{"color": "#8b95a5", "fontSize": ".9rem", "marginTop": "4px"}}>
                            The capstone — <b style={{"color": "#a7b0c0"}}>pandas · pyod · statsmodels</b> doing the numeric heavy lifting, one Jac source.
                        </div>
                    </div>
                </div>

                <div style={{"display": "flex", "gap": "14px", "marginTop": "26px"}}>
                    <div className="stat"><div className="v">{point_count}</div><div className="l">daily points · 129.6k rows</div></div>
                    <div className="stat"><div className="v" style={{"color": "#ff5470"}}>{anomaly_count}</div><div className="l">anomalies · pyod IForest</div></div>
                    <div className="stat"><div className="v" style={{"color": "#2bd4c4"}}>{aic if aic != 0.0 else "—"}</div><div className="l">SARIMAX AIC · forecast fit</div></div>
                </div>

                <div style={{"background": "#0f131c", "border": "1px solid #232a36", "borderRadius": "16px", "padding": "18px 14px 10px", "marginTop": "16px"}}>
                    <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "padding": "0 8px 10px"}}>
                        <div style={{"fontWeight": "600", "fontSize": ".95rem"}}>revenue <span style={{"color": "#5d6b80", "fontWeight": "400"}}>($M / day)</span></div>
                        <div style={{"display": "flex", "gap": "15px", "fontSize": ".74rem", "color": "#8b95a5", "fontFamily": "ui-monospace,monospace"}}>
                            <span><span style={{"color": "#5b8bd4"}}>—</span> actual</span>
                            <span><span style={{"color": "#ff5470"}}>●</span> anomaly</span>
                            <span><span style={{"color": "#2bd4c4"}}>--</span> forecast</span>
                            <span><span style={{"color": "#2bd4c4", "opacity": ".45"}}>▮</span> 95% CI</span>
                        </div>
                    </div>
                    <ResponsiveContainer width="100%" height={340}>
                        <ComposedChart data={chart} margin={{"top": 6, "right": 16, "left": -6, "bottom": 0}}>
                            <CartesianGrid strokeDasharray="3 3" stroke="#1e2634" vertical={False}/>
                            <XAxis dataKey="ts" stroke="#4a5872" fontSize={10.5} tickLine={False} axisLine={False} minTickGap={44}/>
                            <YAxis stroke="#4a5872" fontSize={11} tickLine={False} axisLine={False} width={46}/>
                            <Tooltip contentStyle={{"background": "#121620", "border": "1px solid #2b3444", "borderRadius": "10px", "color": "#e6edf3", "fontSize": ".82rem"}} labelStyle={{"color": "#8b95a5"}} cursor={{"stroke": "#33405a"}}/>
                            <Area dataKey="band" stroke="none" fill="#2bd4c4" fillOpacity={0.10} isAnimationActive={False}/>
                            <Line type="monotone" dataKey="value" stroke="#6aa3ff" strokeWidth={2.5} dot={False}/>
                            <Line type="monotone" dataKey="forecast" stroke="#2bd4c4" strokeWidth={2} strokeDasharray="6 5" dot={False} connectNulls={True} isAnimationActive={False}/>
                            <Line dataKey="anomaly" stroke="none" dot={{"r": 5, "fill": "#ff5470", "stroke": "#0b0d13", "strokeWidth": 2}} isAnimationActive={False}/>
                        </ComposedChart>
                    </ResponsiveContainer>
                </div>

                <div style={{"display": "flex", "gap": "11px", "marginTop": "18px", "alignItems": "center", "flexWrap": "wrap"}}>
                    <button className="mw-btn primary" disabled={busy} onClick={lambda { do_narrate(); }}><Sparkles size={16}/> Narrate anomalies</button>
                    <button className="mw-btn" disabled={busy} onClick={lambda { do_suggest(); }}><Lightbulb size={16}/> Suggest metrics</button>
                    <span style={{"color": "#5d6b80", "fontSize": ".85rem", "fontFamily": "ui-monospace,monospace", "marginLeft": "4px"}}>{status}</span>
                </div>

                {summary and
                    <div className="card" style={{"background": "linear-gradient(160deg, rgba(124,92,255,.10), #10131c)", "border": "1px solid rgba(124,92,255,.28)"}}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "8px", "color": "#9d7bff", "fontSize": ".78rem", "fontFamily": "ui-monospace,monospace", "marginBottom": "10px"}}>
                            <Sparkles size={15}/> INSIGHT · narrated by llm
                        </div>
                        <div style={{"fontWeight": "600", "fontSize": "1.02rem", "lineHeight": "1.5"}}>{summary}</div>
                        <div style={{"marginTop": "12px", "display": "flex", "flexDirection": "column", "gap": "7px"}}>
                            {[<div key={idx} style={{"display": "flex", "gap": "9px", "color": "#a7b0c0", "fontSize": ".92rem"}}>
                                <TriangleAlert size={15} color="#9d7bff" style={{"flexShrink": "0", "marginTop": "3px"}}/>
                                <span>{b}</span>
                            </div> for (idx, b) in enumerate(bullets)]}
                        </div>
                    </div>
                }

                {suggestions and
                    <div className="card">
                        <div style={{"display": "flex", "alignItems": "center", "gap": "8px", "color": "#f0b03a", "fontSize": ".78rem", "fontFamily": "ui-monospace,monospace", "marginBottom": "12px"}}>
                            <Lightbulb size={15}/> SUGGESTED METRICS · by llm
                        </div>
                        <div style={{"display": "flex", "flexDirection": "column", "gap": "10px"}}>
                            {[<div key={idx} style={{"padding": "12px 14px", "background": "#0c0f16", "border": "1px solid #232a36", "borderRadius": "10px"}}>
                                <div style={{"display": "flex", "gap": "10px", "alignItems": "baseline"}}>
                                    <span style={{"fontWeight": "600"}}>{s["name"]}</span>
                                    <code style={{"color": "#2bd4c4", "fontSize": ".82rem", "fontFamily": "ui-monospace,monospace"}}>{s["expression"]}</code>
                                </div>
                                <div style={{"color": "#8b95a5", "fontSize": ".86rem", "marginTop": "5px"}}>{s["rationale"]}</div>
                            </div> for (idx, s) in enumerate(suggestions)]}
                        </div>
                    </div>
                }
            </div>
        </div>;
}
