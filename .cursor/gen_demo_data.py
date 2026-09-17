"""Generate synthetic daily OHLCV CSVs for a self-contained zipline demo.

Writes ``~/zipline_demo/daily/<SYMBOL>.csv`` for a couple of symbols, aligned to
NYSE trading sessions, so the built-in ``csvdir`` bundle can be ingested and the
example algorithms can be backtested without any external data service (Quandl
and the old quantopian-quandl S3 bundle are no longer available).

The AAPL series is shaped with multi-cycle trends so the 100-day / 300-day
moving averages in ``zipline/examples/dual_moving_average.py`` cross several
times, producing a meaningful demo.
"""
import os

import numpy as np
import pandas as pd
from trading_calendars import get_calendar

OUT_DIR = os.path.expanduser("~/zipline_demo/daily")
START = pd.Timestamp("2014-01-02", tz="utc")
END = pd.Timestamp("2017-12-29", tz="utc")
COLUMNS = ["date", "open", "high", "low", "close", "volume"]


def _ohlcv_from_close(close, dates, rng):
    open_ = close * (1 + rng.normal(0, 0.003, size=len(close)))
    high = np.maximum(open_, close) * (1 + np.abs(rng.normal(0, 0.004, size=len(close))))
    low = np.minimum(open_, close) * (1 - np.abs(rng.normal(0, 0.004, size=len(close))))
    volume = rng.randint(1_000_000, 5_000_000, size=len(close))
    return pd.DataFrame(
        {
            "date": dates,
            "open": np.round(open_, 3),
            "high": np.round(high, 3),
            "low": np.round(low, 3),
            "close": np.round(close, 3),
            "volume": volume,
        },
        columns=COLUMNS,
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    sessions = get_calendar("NYSE").sessions_in_range(START, END)
    dates = sessions.tz_localize(None)
    n = len(dates)
    print("NYSE sessions:", n, dates[0].date(), "->", dates[-1].date())

    # AAPL: several up/down trend cycles (longer than the 300-day window) so the
    # dual-moving-average crossover logic actually trades.
    rng = np.random.RandomState(42)
    t = np.arange(n)
    rets = 0.0026 * np.sin(2 * np.pi * t / 380.0) + 0.00005 + rng.normal(0, 0.011, size=n)
    aapl = _ohlcv_from_close(120.0 * np.exp(np.cumsum(rets)), dates, rng)
    aapl.to_csv(os.path.join(OUT_DIR, "AAPL.csv"), index=False)
    print("Wrote AAPL.csv", aapl.shape)

    # A second symbol so the bundle contains more than one asset.
    rng2 = np.random.RandomState(7)
    rets2 = 0.0004 + rng2.normal(0, 0.010, size=n)
    spy = _ohlcv_from_close(200.0 * np.exp(np.cumsum(rets2)), dates, rng2)
    spy.to_csv(os.path.join(OUT_DIR, "SPY.csv"), index=False)
    print("Wrote SPY.csv", spy.shape)
    print("Done. CSV dir:", OUT_DIR)


if __name__ == "__main__":
    main()
