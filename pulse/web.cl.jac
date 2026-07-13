"""Pulse - client dashboard (runs in the browser, compiled from Jac to React).

`sv import` pulls the server walkers in as typed client calls. State lives in
`has` fields (React state); `root spawn <walker>()` invokes the walker over
HTTP with no fetch/CORS glue. The chart is plain SVG built from the same data
the CLI prints.
"""

sv import from api { seed, scan, forecast, narrate, series_points }

def:pub app -> JsxElement {
    has points: list = [],
        anomalies: list = [],
        summary: str = "",
        bullets: list = [],
        status: str = "loading…";

    # runs once on mount: seed if empty, load points, run an initial scan
    can with entry {
        boot();
    }

    async def boot -> None;
    async def do_scan -> None;
    async def do_forecast -> None;
    async def do_narrate -> None;
    def chart_svg -> str;

    return
        <div style={{
            "minHeight": "100vh",
            "background": "#0b0e14",
            "color": "#e6edf3",
            "fontFamily": "system-ui, -apple-system, sans-serif"
        }}>
            <div style={{"maxWidth": "820px", "margin": "0 auto", "padding": "44px 20px"}}>
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <div style={{"width": "12px", "height": "12px", "borderRadius": "50%", "background": "#ff6a3d"}}></div>
                    <h1 style={{"margin": "0", "fontSize": "1.7rem", "letterSpacing": "-0.02em"}}>Pulse</h1>
                </div>
                <p style={{"color": "#93a0b4", "marginTop": "6px"}}>
                    The same walkers as the CLI — now in a browser. No fetch, no CORS, no glue.
                </p>

                <div style={{
                    "background": "#11151d", "border": "1px solid #232a36",
                    "borderRadius": "14px", "padding": "18px 18px 8px", "marginTop": "22px"
                }}>
                    <div dangerouslySetInnerHTML={{"__html": chart_svg()}}/>
                    <div style={{"fontFamily": "monospace", "fontSize": "0.75rem", "color": "#5d6b80", "padding": "4px 2px 8px"}}>
                        orders · anomalies flagged by scan
                    </div>
                </div>

                <div style={{"display": "flex", "gap": "10px", "marginTop": "18px", "flexWrap": "wrap", "alignItems": "center"}}>
                    <button onClick={lambda -> None { do_scan(); }} style={{
                        "padding": "10px 18px", "background": "#161b26", "color": "#e6edf3",
                        "border": "1px solid #2b6", "borderColor": "#2f3a4a", "borderRadius": "9px", "cursor": "pointer", "fontWeight": "600"
                    }}>Scan</button>
                    <button onClick={lambda -> None { do_forecast(); }} style={{
                        "padding": "10px 18px", "background": "#161b26", "color": "#e6edf3",
                        "border": "1px solid #2f3a4a", "borderRadius": "9px", "cursor": "pointer", "fontWeight": "600"
                    }}>Forecast</button>
                    <button onClick={lambda -> None { do_narrate(); }} style={{
                        "padding": "10px 18px", "background": "linear-gradient(100deg,#ff6a3d,#ff8a52)",
                        "color": "#1a0d08", "border": "none", "borderRadius": "9px", "cursor": "pointer", "fontWeight": "700"
                    }}>Narrate ✦</button>
                    <span style={{"color": "#5d6b80", "fontSize": "0.85rem", "fontFamily": "monospace"}}>{status}</span>
                </div>

                {summary and
                    <div style={{
                        "marginTop": "20px", "padding": "20px 22px", "borderRadius": "14px",
                        "background": "#150f0d", "border": "1px solid #59331f"
                    }}>
                        <div style={{"color": "#ff6a3d", "fontSize": "0.8rem", "fontFamily": "monospace", "marginBottom": "8px"}}>✦ Insight · authored by llm</div>
                        <div style={{"fontWeight": "600"}}>{summary}</div>
                        <ul style={{"margin": "12px 0 0", "paddingLeft": "20px", "color": "#93a0b4"}}>
                            {[<li key={idx} style={{"margin": "4px 0"}}>{b}</li> for (idx, b) in enumerate(bullets)]}
                        </ul>
                    </div>
                }
            </div>
        </div>;
}
