#!/bin/sh
# Real startups of `nvim diff` (VimEnter, argv detection, layout, quit on close), which
# `nvim -l` cannot cover. Run with `make smoke`.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NVIM=${NVIM:-nvim}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
OUT="$TMP/out"
export OUT
FAILED=0

REPO="$TMP/repo"
mkdir -p "$REPO/sub" "$TMP/norepo"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
echo one >"$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" -c commit.gpgsign=false commit -qm init
echo two >"$REPO/a.txt"

# Writes key=value facts about the editor to $OUT, then quits
REPORT="lua vim.defer_fn(function()
  local s = require('nvim-diff.view').session
  vim.fn.writefile({
    'open=' .. tostring(s ~= nil),
    'quit_on_close=' .. tostring(s and s.quit_on_close or false),
    'wins=' .. #vim.api.nvim_tabpage_list_wins(0),
    'tabs=' .. #vim.api.nvim_list_tabpages(),
    'current=' .. (s and s.current and s.current.path or ''),
    'bufname=' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'),
    'diff_buf=' .. vim.fn.bufexists('diff'),
  }, vim.env.OUT)
  vim.cmd('qa!')
end, 300)"

start() { # dir, extra args...
    dir=$1
    shift
    rm -f "$OUT"
    (cd "$dir" && "$NVIM" --clean --headless --cmd "set rtp^=$ROOT" "$@" >/dev/null 2>&1) || true
}

expect() { # scenario, key=value...
    name=$1
    shift
    for kv in "$@"; do
        if ! grep -qx "$kv" "$OUT" 2>/dev/null; then
            echo "FAIL  $name: expected $kv, got:"
            sed 's/^/      /' "$OUT" 2>/dev/null || echo "      (no report)"
            FAILED=1
            return
        fi
    done
    echo "ok    $name"
}

start "$REPO/sub" diff "+$REPORT"
expect "nvim diff in a repo subfolder opens the view" \
    open=true quit_on_close=true wins=3 tabs=1 current=a.txt diff_buf=0

start "$TMP/norepo" diff "+$REPORT"
expect "nvim diff outside a repo: normal empty editor" open=false diff_buf=0 bufname=

echo "a file named diff" >"$TMP/norepo/diff"
start "$TMP/norepo" diff "+$REPORT"
expect "nvim diff with a file named diff opens that file" open=false bufname=diff
rm "$TMP/norepo/diff"

start "$REPO" "+$REPORT"
expect "plain nvim does not open the view" open=false

# Closing the view quits Neovim: the fallback report must never be written
start "$REPO" diff "+lua vim.defer_fn(function() require('nvim-diff').close() end, 300)" \
    "+lua vim.defer_fn(function() vim.fn.writefile({ 'still=running' }, vim.env.OUT) vim.cmd('qa!') end, 2000)"
if [ -e "$OUT" ]; then
    echo "FAIL  closing the view quits Neovim"
    FAILED=1
else
    echo "ok    closing the view quits Neovim"
fi

exit $FAILED
