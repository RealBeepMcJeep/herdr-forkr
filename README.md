# forkr

Fork the focused agent's conversation into a new tab, split, or workspace in
[Herdr](https://herdr.dev), and keep the original running.

One keypress on a pane running Claude Code, Codex, Pi, or OpenCode opens a copy
of that conversation next to it, in the same working directory. The copy gets
its own session id, so you can take it in a different direction while the
original keeps going, even if it is mid-turn.

| Agent | What the new pane runs |
| --- | --- |
| Claude Code | `claude --resume <id> --fork-session` |
| Codex | `codex fork <id>` |
| Pi | `pi --fork <session-file-or-id>` |
| OpenCode | `opencode --session <id> --fork` |

## How it works

forkr is about a hundred lines of POSIX shell. It does four things:

1. Asks Herdr for the focused pane's agent and native session reference
   (`herdr agent get`). Herdr's integration for that agent is what reports the
   reference, so it must be installed.
2. Opens the destination in the same working directory with `herdr tab create`,
   `herdr pane split`, or `herdr workspace create`.
3. Starts the same agent there with its fork flags through `herdr agent start`,
   which returns once Herdr has detected the agent and it is ready for input.
4. Shows a toast naming the source and destination panes.

Because the fork runs directly in an ordinary pane, Herdr treats it like any
agent you started yourself: live status in the sidebar, `herdr agent` commands,
and native session restore after a server restart. There is no wrapper process
and nothing is written to disk.

## Requirements

- Herdr 0.8.0 or newer (tested on 0.8.2, Linux)
- [`jq`](https://jqlang.github.io/jq/) on `PATH`
- The agent CLI you fork on `PATH`, and its Herdr integration installed:
  `herdr integration install claude`, `codex`, `pi`, or `opencode`
  (check with `herdr integration status`)

## Install

```sh
herdr plugin install t4t5/herdr-forkr
```

Or link a local checkout:

```sh
herdr plugin link /path/to/herdr-forkr
```

## Bind keys

Add to `~/.config/herdr/config.toml` (any free bindings work):

```toml
[[keys.command]]
key = "prefix+f"
type = "plugin_action"
command = "forkr.tab"
description = "fork agent conversation into new tab"

[[keys.command]]
key = "prefix+shift+f"
type = "plugin_action"
command = "forkr.split"
description = "fork agent conversation into split pane"
```

Then `herdr server reload-config`. The actions also appear in a pane's
right-click menu.

## Actions

| Action | Destination |
| --- | --- |
| `forkr.tab` | New tab in the same workspace |
| `forkr.split` | Pane to the right of the source pane |
| `forkr.split-down` | Pane below the source pane |
| `forkr.workspace` | New workspace |

All of them focus the new pane. Every action reads the pane Herdr reports as
focused; from a keybinding or the pane menu that is the pane you are on.

## From a script

`forkr.sh` also works outside the plugin system and prints the new pane id:

```sh
sh forkr.sh [--tab | --split [right|down] | --workspace] [--no-focus] [pane-id|agent-name]
```

Without a target it uses `HERDR_PANE_ID`, so a script running inside a Herdr
pane forks that pane. `--no-focus` leaves focus where it is.

## Notes

- The fork is a snapshot of the transcript as saved on disk when you press the
  key. A turn that is still running is not in the copy.
- Claude Code's "allow for this session" grants belong to the original process;
  the fork asks again.
- Pi: Herdr reports the session file path, which `pi --fork` accepts directly.
  The fork is saved under Pi's sessions directory for the new pane's working
  directory, the same one as the original.
- If the agent shows a prompt at startup (a trust dialog, a hook approval), the
  pane is left for you to answer and forkr says nothing. If Herdr has not
  detected the agent after 60 seconds, the toast says so and the pane stays
  open.
- Errors are shown as Herdr toasts, because plugin actions run detached.

## Related plugins

- [dmangla3/herdr-fork-from-message](https://github.com/dmangla3/herdr-fork-from-message):
  Claude Code and Codex, lets you pick an earlier message as the fork point.
- [calebcauthon/herdr-agent-copy-paste-fork](https://github.com/calebcauthon/herdr-agent-copy-paste-fork):
  Claude Code and Codex (Pi and OpenCode in
  [PR #2](https://github.com/calebcauthon/herdr-agent-copy-paste-fork/pull/2)),
  plus a copy/paste fork clipboard. Runs the fork under a PTY recorder inside a
  plugin pane.
- [potatoQi/herdr-focused-codex-fork](https://github.com/potatoQi/herdr-focused-codex-fork):
  Codex only, split to the right.

forkr differs in the launch path: a plain pane plus `herdr agent start`, no
wrapper process, so Herdr sees the fork as a normal agent.

## Development

```sh
herdr plugin link .
herdr plugin action list --plugin forkr
herdr plugin log list --plugin forkr
sh -n forkr.sh
```

## License

MIT, see [LICENSE](LICENSE).
