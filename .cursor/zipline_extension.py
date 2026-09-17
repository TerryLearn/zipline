"""Zipline extension installed to ~/.zipline/extension.py by .cursor/install.sh.

Registers the built-in ``csvdir`` bundle against the locally generated demo
CSVs (see .cursor/gen_demo_data.py) with an explicit NYSE session range so
``zipline ingest -b csvdir`` and ``zipline run --bundle csvdir`` work without
any external data service.
"""
import os

import pandas as pd

from zipline.data.bundles import register
from zipline.data.bundles.csvdir import csvdir_equities

CSVDIR = os.path.expanduser("~/zipline_demo")

register(
    "csvdir",
    csvdir_equities(["daily"], CSVDIR),
    calendar_name="NYSE",
    start_session=pd.Timestamp("2014-01-02", tz="utc"),
    end_session=pd.Timestamp("2017-12-29", tz="utc"),
)
