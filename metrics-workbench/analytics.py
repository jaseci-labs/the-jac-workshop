"""Analytics helpers — pandas / statsmodels / pyod.

Kept in Python because this is what the ecosystem is best at. The Jac side
in api.jac holds the graph model, walkers, and orchestration; this module
holds the numerical work.
"""

from __future__ import annotations

import json
from typing import Any

import pandas as pd
from pyod.models.iforest import IForest
from statsmodels.tsa.statespace.sarimax import SARIMAX


def load_frame(path: str) -> pd.DataFrame:
    if path.endswith(".parquet"):
        return pd.read_parquet(path)
    return pd.read_csv(path)


def describe_dataset(path: str) -> dict:
    df = load_frame(path)
    return {
        "row_count": int(len(df)),
        "columns": [str(c) for c in df.columns],
        "dtypes": {str(c): str(df[c].dtype) for c in df.columns},
    }


def compute_metric_series(
    path: str, expression: str, time_column: str
) -> pd.Series:
    """Evaluate a pandas expression against a dataset, return an indexed series."""
    df = load_frame(path)
    df[time_column] = pd.to_datetime(df[time_column])
    df = df.sort_values(time_column)
    # `expression` is evaluated with df.eval — supports column names and
    # arithmetic (e.g. "gross_revenue - refunds"). Not general Python.
    values = df.eval(expression)
    return pd.Series(values.values, index=df[time_column].values, name=expression)


def preview_metric(
    path: str, expression: str, time_column: str, n: int
) -> list[dict]:
    series = compute_metric_series(path, expression, time_column)
    # Aggregate to daily granularity so previews are readable across long ranges.
    daily = series.resample("D").sum()
    head = daily.iloc[:n]
    return [
        {"ts": str(ts), "value": float(v)}
        for ts, v in head.items()
    ]


def detect_anomalies(
    path: str,
    expression: str,
    time_column: str,
    window_days: int,
    algorithm: str,
) -> dict:
    series = compute_metric_series(path, expression, time_column)
    daily = series.resample("D").sum().dropna()
    # Restrict to the requested trailing window if the series is longer.
    if window_days > 0 and len(daily) > window_days:
        daily = daily.iloc[-window_days:]

    if algorithm != "iforest":
        raise ValueError(f"unsupported algorithm: {algorithm}")

    values = daily.values.reshape(-1, 1)
    model = IForest(contamination=0.05, random_state=42)
    model.fit(values)
    labels = model.labels_              # 1 = outlier, 0 = inlier
    scores = model.decision_scores_

    points = []
    for ts, val, label, score in zip(daily.index, daily.values, labels, scores):
        points.append(
            {
                "ts": str(ts),
                "value": float(val),
                "score": float(score),
                "is_anomaly": bool(label),
            }
        )
    anomaly_count = int(sum(labels))
    return {
        "points": points,
        "anomaly_count": anomaly_count,
        "window_days": int(window_days),
        "algorithm": algorithm,
    }


def forecast(
    path: str,
    expression: str,
    time_column: str,
    horizon_days: int,
    seasonality: str,
) -> dict:
    series = compute_metric_series(path, expression, time_column)
    daily = series.resample("D").sum().dropna()

    seasonal_period = {"weekly": 7, "monthly": 30, "none": 0}.get(seasonality, 7)
    order = (1, 1, 1)
    seasonal_order = (
        (1, 1, 1, seasonal_period) if seasonal_period else (0, 0, 0, 0)
    )

    model = SARIMAX(
        daily.values,
        order=order,
        seasonal_order=seasonal_order,
        enforce_stationarity=False,
        enforce_invertibility=False,
    )
    fit = model.fit(disp=False)
    pred = fit.get_forecast(steps=horizon_days)
    mean = pred.predicted_mean
    ci = pred.conf_int(alpha=0.05)

    last_ts = pd.to_datetime(daily.index[-1])
    future_index = pd.date_range(
        start=last_ts + pd.Timedelta(days=1), periods=horizon_days, freq="D"
    )

    points = []
    for i, ts in enumerate(future_index):
        points.append(
            {
                "ts": str(ts),
                "forecast": float(mean[i]),
                "lower": float(ci[i, 0]),
                "upper": float(ci[i, 1]),
            }
        )
    return {
        "points": points,
        "horizon_days": int(horizon_days),
        "seasonality": seasonality,
        "aic": float(fit.aic),
    }


def web_dashboard(
    path: str,
    expression: str,
    time_column: str,
    window_days: int = 90,
    horizon_days: int = 30,
    seasonality: str = "weekly",
) -> dict:
    """One chart-ready payload for the web UI: the daily series with anomaly
    flags, plus a forecast with confidence band, merged onto one date axis."""
    series = compute_metric_series(path, expression, time_column)
    daily = series.resample("D").sum().dropna()
    if window_days > 0 and len(daily) > window_days:
        daily = daily.iloc[-window_days:]

    values = daily.values.reshape(-1, 1)
    model = IForest(contamination=0.05, random_state=42)
    model.fit(values)
    labels = model.labels_
    anom_idx = {i for i, lbl in enumerate(labels) if lbl == 1}

    fc = forecast(path, expression, time_column, horizon_days, seasonality)

    # scale to millions for a readable axis (the demo metric is revenue in $)
    chart: list[dict] = []
    for i, (ts, v) in enumerate(daily.items()):
        mv = round(float(v) / 1e6, 2)
        chart.append(
            {
                "ts": str(ts)[:10],
                "value": mv,
                "anomaly": mv if i in anom_idx else None,
            }
        )
    for p in fc["points"]:
        chart.append(
            {
                "ts": str(p["ts"])[:10],
                "forecast": round(p["forecast"] / 1e6, 2),
                "band": [round(p["lower"] / 1e6, 2), round(p["upper"] / 1e6, 2)],
            }
        )
    return {
        "chart": chart,
        "anomaly_count": int(len(anom_idx)),
        "point_count": int(len(daily)),
        "aic": round(float(fc["aic"]), 1),
        "horizon": int(horizon_days),
    }


def summarize_run_for_narration(kind: str, output_json: str) -> str:
    """Produce a compact human-readable string for the LLM to narrate over.

    We give the LLM structured findings, not raw arrays — smaller prompt,
    more predictable output.
    """
    output = json.loads(output_json)
    if kind == "anomaly":
        anomalies = [p for p in output["points"] if p["is_anomaly"]]
        first = anomalies[:3]
        return json.dumps(
            {
                "kind": "anomaly",
                "window_days": output.get("window_days"),
                "algorithm": output.get("algorithm"),
                "total_points": len(output["points"]),
                "anomaly_count": output.get("anomaly_count"),
                "example_anomalies": first,
            }
        )
    if kind == "forecast":
        first = output["points"][:3]
        last = output["points"][-3:]
        return json.dumps(
            {
                "kind": "forecast",
                "horizon_days": output.get("horizon_days"),
                "seasonality": output.get("seasonality"),
                "aic": output.get("aic"),
                "first_points": first,
                "last_points": last,
            }
        )
    return output_json


def output_anomaly_summary(output_json: str) -> str:
    d = json.loads(output_json)
    return f"anomalies={d.get('anomaly_count', 0)}/{len(d.get('points', []))}"


def output_forecast_summary(output_json: str) -> str:
    d = json.loads(output_json)
    return f"aic={d.get('aic', 0.0):.1f} horizon={d.get('horizon_days', 0)}d"


def output_field_int(output_json: str, field: str) -> int:
    d = json.loads(output_json)
    v = d.get(field, 0)
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def dataset_info_row_count(path: str) -> int:
    return int(describe_dataset(path)["row_count"])


def dataset_info_columns(path: str) -> list[str]:
    return [str(c) for c in describe_dataset(path)["columns"]]


def to_json(obj: Any) -> str:
    return json.dumps(obj, default=str, indent=2)


def json_dumps(obj: Any) -> str:
    return json.dumps(obj, default=str)
