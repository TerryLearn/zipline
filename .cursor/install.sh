#!/usr/bin/env bash
#
# Cloud Agent install script for zipline (this repo targets Python 3.6 and a
# pinned scientific stack). The script is idempotent so it is safe to run
# repeatedly and to bake into an environment build snapshot.
#
# It:
#   1. installs Miniconda (provides Python 3.6),
#   2. creates a conda env with a compiled bcolz + TA-Lib,
#   3. pip-installs zipline (editable) and its dev/test tooling using the
#      repo's pinned constraints,
#   4. sets up a self-contained ``csvdir`` data bundle so backtests run without
#      any external data service (Quandl/quantopian-quandl are no longer
#      available), and
#   5. auto-activates the env in interactive shells.
#
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

CONDA_DIR="$HOME/miniconda3"
ENV_NAME="zipline"
CF="-c conda-forge --override-channels"

echo "==> [1/8] Miniconda"
if [ ! -x "$CONDA_DIR/bin/conda" ]; then
    curl -fsSL -o /tmp/miniconda.sh \
        https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash /tmp/miniconda.sh -b -p "$CONDA_DIR"
fi
# shellcheck disable=SC1091
source "$CONDA_DIR/etc/profile.d/conda.sh"

echo "==> [2/8] conda env ($ENV_NAME, python 3.6)"
if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    conda create -y -n "$ENV_NAME" $CF python=3.6
fi
conda activate "$ENV_NAME"

echo "==> [3/8] bcolz (prebuilt; its bundled c-blosc will not compile on modern gcc)"
python -c "import bcolz" 2>/dev/null || conda install -y $CF --no-deps "bcolz=1.2.1"

echo "==> [4/8] TA-Lib C library (built from source for the 0.4.x soname)"
if [ ! -f /usr/lib/libta_lib.so.0 ]; then
    curl -fsSL -o /tmp/ta-lib-src.tar.gz \
        https://downloads.sourceforge.net/project/ta-lib/ta-lib/0.4.0/ta-lib-0.4.0-src.tar.gz
    rm -rf /tmp/ta-lib && tar xzf /tmp/ta-lib-src.tar.gz -C /tmp
    ( cd /tmp/ta-lib && ./configure --prefix=/usr && make && sudo make install )
    sudo ldconfig
fi

echo "==> [5/8] base build tooling (pinned to match the era of this codebase)"
python -m pip install "pip==20.3.4" "setuptools<46" "wheel"

# Build a constraints file from the repo's locked requirements, dropping the
# editable git+git:// blaze/odo/datashape lines (that protocol is dead and the
# optional blaze pipeline loader is not needed to run zipline) and inline
# comments / extras that a pip constraints file cannot parse.
CONSTRAINTS=/tmp/zipline_constraints.txt
grep -v '^-e ' etc/requirements_py36_locked.txt \
    | sed 's/#.*//' \
    | sed 's/\[[^]]*\]//' \
    | sed 's/[[:space:]]*$//' \
    | grep -vE '^\s*$' > "$CONSTRAINTS"

echo "==> [6/8] build requirements (Cython, numpy, setuptools-scm)"
python -m pip install -r etc/requirements_build.in -c "$CONSTRAINTS"

echo "==> [7/8] zipline (editable), dev/test tooling, and TA-Lib wrapper"
python -m pip install -e . -c "$CONSTRAINTS" --use-deprecated=legacy-resolver
python -m pip install -r etc/requirements_dev.in -c "$CONSTRAINTS" --use-deprecated=legacy-resolver
TA_INCLUDE_PATH=/usr/include TA_LIBRARY_PATH=/usr/lib \
    python -m pip install --no-binary=ta-lib "TA-Lib==0.4.18" \
    -c "$CONSTRAINTS" --use-deprecated=legacy-resolver

echo "==> [8/8] self-contained csvdir data bundle + shell auto-activation"
mkdir -p "$HOME/.zipline"
cp "$REPO_DIR/.cursor/zipline_extension.py" "$HOME/.zipline/extension.py"
python "$REPO_DIR/.cursor/gen_demo_data.py"
zipline ingest -b csvdir

conda init bash >/dev/null 2>&1 || true
if ! grep -q "conda activate $ENV_NAME" "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# Auto-activate the zipline conda env for Cloud Agent shells\nconda activate %s\n' "$ENV_NAME" >> "$HOME/.bashrc"
fi

echo
echo "Install complete. In a new shell: 'zipline --help'"
echo "Run the demo backtest with:"
echo "  MPLBACKEND=Agg zipline run -f zipline/examples/dual_moving_average.py \\"
echo "    --bundle csvdir --start 2014-6-2 --end 2017-12-29 \\"
echo "    --capital-base 100000 -o /tmp/dma.pickle --no-benchmark"
