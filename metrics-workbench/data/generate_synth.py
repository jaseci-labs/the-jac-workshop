"""Generate synthetic e-commerce operational time-series for the workbench.

Produces a CSV with 1-minute granularity across ~90 days, with three
deliberately-injected anomalies so anomaly detection has something to find:

1. A 48h promo spike (orders + revenue jump).
2. A 3h EU-region outage (orders drop to zero, error_rate spikes).
3. A 2-week slow latency degradation.

Usage:
    python generate_synth.py                       # writes ./synth_ecom.csv
    python generate_synth.py /tmp/out.csv          # custom path
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd


def generate(days: int = 90, seed: int = 42) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    # 1-minute cadence over `days`.
    n = days * 24 * 60
    start = pd.Timestamp("2026-04-01 00:00:00")
    ts = pd.date_range(start=start, periods=n, freq="1min")

    minutes = np.arange(n)
    hour = (minutes // 60) % 24
    day_of_week = (minutes // (60 * 24)) % 7

    # Daily seasonality + weekly seasonality + trend.
    diurnal = 200 + 150 * np.sin((hour - 6) / 24 * 2 * np.pi)
    weekly = 40 * (day_of_week >= 5)  # weekend bump
    trend = np.linspace(0, 60, n)
    base_orders = diurnal + weekly + trend + rng.normal(0, 15, n)
    base_orders = np.clip(base_orders, 0, None)

    channel = rng.choice(["web", "mobile", "partner"], size=n, p=[0.6, 0.35, 0.05])
    region = rng.choice(["NA", "EU", "APAC", "LATAM"], size=n, p=[0.4, 0.3, 0.2, 0.1])

    orders = base_orders.copy()
    aov = rng.normal(65, 8, n).clip(20, 200)
    gross_revenue = orders * aov
    refunds = gross_revenue * rng.uniform(0.01, 0.04, n)
    page_load_ms_p95 = 800 + 60 * np.sin((hour - 3) / 24 * 2 * np.pi) + rng.normal(0, 40, n)
    error_rate = np.clip(0.005 + rng.normal(0, 0.002, n), 0, 1)

    # Anomaly 1: 48h promo spike, days 30-32.
    promo_start = 30 * 24 * 60
    promo_end = 32 * 24 * 60
    orders[promo_start:promo_end] *= 2.3
    gross_revenue[promo_start:promo_end] *= 2.5

    # Anomaly 2: 3h EU outage, day 55 at 14:00.
    outage_start = 55 * 24 * 60 + 14 * 60
    outage_end = outage_start + 3 * 60
    eu_mask = region == "EU"
    outage_window = np.zeros(n, dtype=bool)
    outage_window[outage_start:outage_end] = True
    hit = eu_mask & outage_window
    orders[hit] = 0
    gross_revenue[hit] = 0
    error_rate[hit] = np.clip(error_rate[hit] + 0.4, 0, 1)

    # Anomaly 3: 2-week gradual latency degradation, days 70-84.
    deg_start = 70 * 24 * 60
    deg_end = 84 * 24 * 60
    ramp = np.linspace(0, 500, deg_end - deg_start)
    page_load_ms_p95[deg_start:deg_end] += ramp

    return pd.DataFrame(
        {
            "order_ts": ts,
            "region": region,
            "channel": channel,
            "orders": orders.round().astype(int),
            "gross_revenue": gross_revenue.round(2),
            "refunds": refunds.round(2),
            "page_load_ms_p95": page_load_ms_p95.round(1),
            "error_rate": error_rate.round(4),
        }
    )


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("synth_ecom.csv")
    df = generate()
    df.to_csv(out, index=False)
    print(f"wrote {len(df):,} rows to {out}")
