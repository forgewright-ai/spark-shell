#!/bin/sh
# semantic search measured on the real thing (v0.130): the providers in a scratch home, the dialog's own
# candidates, EmbeddingGemma 2 served by spark's llama.cpp server on a socket of the scratch home, and the frozen
# requests in test/semantic_cases.json. By hand, where spark and the model are installed; CI skips it.
#   sh test/semantic_measure.sh [MODEL.gguf] [OUT] [fill]
# With fill, each lit step that takes values is filled by your spark, as the dialog asks it: spark runs with your
# own home (its config and its model server), so it keeps its timing numbers of those requests, and nothing else.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
model=${1:-${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/models/embeddinggemma-2-Q8_0.gguf}
out=${2:-}
fill=''
if [ "${3:-}" = fill ]; then
    real_spark=$(command -v spark) || { echo "no spark here to fill with" >&2; exit 1; }
    fill=yes
fi
engine=$(ls -d "${XDG_DATA_HOME:-$HOME/.local/share}"/spark/engine/*/llama-server 2>/dev/null | sort -V | tail -1)
[ -x "$engine" ] || { echo "no llama-server from spark here" >&2; exit 1; }
[ -s "$model" ] || { echo "no model at $model" >&2; exit 1; }
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
h=$(mktemp -d "${TMPDIR:-/tmp}/semantic-measure.XXXX")
sock="$h/semantic.sock"
"$engine" -m "$model" --embedding --pooling mean --host "$sock" -ngl 0 -t 4 -c 2048 -b 2048 -ub 2048 \
    --no-webui --log-disable --offline </dev/null >"$h/server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -rf "$h"' EXIT INT TERM
i=0
until curl -sf --unix-socket "$sock" http://localhost/health >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 100 ] || { echo "the server did not start" >&2; exit 1; }
    sleep 0.2
done
mkdir -p "$h/home/.config" "$h/home/.local/state" "$h/home/.cache" "$h/home/.local/share"
if [ -n "$fill" ]; then
    printf '#!/bin/sh\nexec env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME HOME="%s" "%s" "$@"\n' \
        "$HOME" "$real_spark" > "$h/spark"
    chmod 700 "$h/spark"
    export SPARK_SHELL_MEASURE_SPARK="$h/spark"
fi
cd "$repo/component/dialog"
HOME="$h/home" XDG_CONFIG_HOME="$h/home/.config" XDG_STATE_HOME="$h/home/.local/state" XDG_CACHE_HOME="$h/home/.cache" \
XDG_DATA_HOME="$h/home/.local/share" SPARK_SHELL_REPO="$repo" SPARK_SHELL_SEMANTIC_SOCK="$sock" \
SPARK_SHELL_SEMANTIC_CASES="${SPARK_SHELL_SEMANTIC_CASES:-$repo/test/semantic_cases.json}" SPARK_SHELL_SEMANTIC_OUT="${out:-$h/out.txt}" \
    cargo test --locked --test semantic_measure -- --ignored --nocapture 2>&1 | sed -n '/candidates from/,/^test result/p' | grep -v '^test result'
