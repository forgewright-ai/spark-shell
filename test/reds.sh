#!/bin/sh
# test/reds.sh OWNER/REPO SHA -- the attempts of ci.yml on SHA that failed, one a line: "BRANCH run ID attempt N".
# Nothing printed: every run of the commit passed at its first try, or was cancelled. Exit 2 when GitHub's answer
# cannot be read. Read by test/tag.sh and by release.yml: a release on a commit that was red says why. GitHub is
# asked with gh where GH_TOKEN is set, else with no token through curl (SPARK_SHELL_TAG_CURL names it, a test's seam).
set -eu
repo=${1:?OWNER/REPO}; sha=${2:?SHA}
CURL=${SPARK_SHELL_TAG_CURL:-curl}
get() {
    if [ -n "${GH_TOKEN:-}" ]; then gh api "$1"
    else "$CURL" -fsS -m 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"; fi 2>/dev/null
}
runs=$(get "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$sha&event=push&per_page=50") || exit 2
list=$(printf '%s' "$runs" | jq -r --arg sha "$sha" '.workflow_runs[] | select(.head_sha == $sha and .event == "push") | "\(.id) \(.run_attempt) \(.conclusion // "none") \(.head_branch)"' 2>/dev/null) || exit 2
[ -n "$list" ] || exit 2
while read -r id n end branch; do
    case $n in ''|0|*[!0-9]*) exit 2 ;; esac
    k=1
    while [ "$k" -lt "$n" ]; do
        was=$(get "repos/$repo/actions/runs/$id/attempts/$k" | jq -r '.conclusion // "none"' 2>/dev/null) || exit 2
        case $was in failure) echo "$branch run $id attempt $k" ;; '') exit 2 ;; esac
        k=$((k + 1))
    done
    [ "$end" != failure ] || echo "$branch run $id attempt $n"
done <<EOF
$list
EOF
