#!/bin/sh
# forkr: fork the focused agent's conversation into a new tab, split, or
# workspace, and keep the original running.
#
# herdr's agent integrations report each pane's native session reference.
# forkr reads it, opens the destination in the same working directory, and
# starts the same agent there in its own fork mode through `herdr agent
# start`, so herdr detects the fork like any agent you launched by hand.
# The fork gets a new session id; both conversations continue independently.
#
# Usage: forkr.sh [--tab | --split [right|down] | --workspace] [--no-focus]
#                 [pane-id | agent-name]
#
# Without a target, the focused pane is used (herdr passes it to plugin
# actions). Prints the new pane id on success. Plugin actions run detached,
# so results and errors are also shown as herdr toasts.

set -u

herdr=${HERDR_BIN_PATH:-herdr}

notify() {
  "$herdr" notification show "forkr" --body "$1" --sound "${2:-none}" >/dev/null 2>&1
}

fail() {
  notify "$1" request
  printf 'forkr: %s\n' "$1" >&2
  exit 1
}

dest=tab
direction=right
focus=--focus
target=
while [ $# -gt 0 ]; do
  case $1 in
    --tab) dest=tab ;;
    --workspace) dest=workspace ;;
    --split)
      dest=split
      case ${2:-} in right|down) direction=$2; shift ;; esac
      ;;
    --no-focus) focus=--no-focus ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) fail "unknown option $1" ;;
    *) target=$1 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || fail "jq is required but not on PATH"

# Target: explicit argument, else the pane herdr says is focused.
if [ -z "$target" ] && [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
  target=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_id // empty')
fi
[ -n "$target" ] || target=${HERDR_PANE_ID:-}
[ -n "$target" ] || target=$("$herdr" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty')
[ -n "$target" ] || fail "no focused pane"

info=$("$herdr" agent get "$target" 2>/dev/null) || fail "no agent running in $target"
field() { printf '%s' "$info" | jq -r ".result.agent.$1 // empty"; }
kind=$(field agent)
pane_id=$(field pane_id)
workspace=$(field workspace_id)
cwd=$(field foreground_cwd)
[ -n "$cwd" ] || cwd=$(field cwd)
ref_kind=$(field agent_session.kind)
ref=$(field agent_session.value)

[ -n "$ref" ] || fail "herdr has no session for the $kind in $pane_id. Install its integration: herdr integration install $kind"

# Each agent's own fork entry point. The list becomes the agent's argv.
case $kind in
  claude)   set -- --resume "$ref" --fork-session ;;
  codex)    set -- fork "$ref" ;;
  pi)       set -- --fork "$ref" ;;         # takes a session file or id
  opencode) set -- --session "$ref" --fork ;;
  *) fail "no fork recipe for $kind" ;;
esac
if [ "$ref_kind" != id ] && [ "$kind" != pi ]; then
  fail "$kind reported a session $ref_kind, expected an id"
fi

case $dest in
  tab)
    out=$("$herdr" tab create --workspace "$workspace" --cwd "$cwd" "$focus" 2>&1) \
      || fail "could not create a tab: $out"
    new_pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')
    ;;
  split)
    out=$("$herdr" pane split "$pane_id" --direction "$direction" --cwd "$cwd" "$focus" 2>&1) \
      || fail "could not split $pane_id: $out"
    new_pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id // empty')
    ;;
  workspace)
    out=$("$herdr" workspace create --cwd "$cwd" "$focus" 2>&1) \
      || fail "could not create a workspace: $out"
    new_pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')
    ;;
esac
[ -n "$new_pane" ] || fail "herdr returned no pane id: $out"

# A brand-new pane may still be starting its shell, and agent start refuses
# a pane that is not at an interactive prompt. Wait (up to 10s) until the
# only foreground process is the shell itself.
i=0
while [ $i -lt 50 ]; do
  ready=$("$herdr" pane process-info --pane "$new_pane" 2>/dev/null | jq -r '
    .result.process_info
    | if (.foreground_processes | length) == 1
         and (.foreground_processes[0].pid == .shell_pid
              or (.foreground_processes[0].name | test("^(zsh|bash|fish|sh|dash|ksh|nu)$")))
      then "yes" else "no" end' 2>/dev/null)
  [ "$ready" = yes ] && break
  i=$((i + 1))
  sleep 0.2
done

# agent start needs a unique name; clear it afterwards so the sidebar keeps
# the agent's own title. A blocked startup (trust prompt, hook approval)
# still leaves a usable pane, so only other failures are reported.
err=$("$herdr" agent start "forkr-$$" --kind "$kind" --pane "$new_pane" --timeout 60000 -- "$@" 2>&1 >/dev/null)
status=$?
"$herdr" agent rename "$new_pane" --clear >/dev/null 2>&1
if [ $status -ne 0 ] && ! printf '%s' "$err" | grep -q agent_not_ready; then
  fail "$kind did not start in $new_pane: $err"
fi

notify "Forked $kind: $pane_id -> $new_pane"
printf '%s\n' "$new_pane"
