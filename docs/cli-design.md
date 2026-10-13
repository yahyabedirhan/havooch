# The havooch command: CLI design

This document is the design of the `havooch` command as its callers see it: the command tree, the words and flags, what each command prints and how it fails, the help, and the rules that keep them consistent. It follows the CLI design delivery framework (`/cli-design`). The code behind it is in `docs/low-level-design.md`, under ReviewCommand.

Read this document before you add, rename or remove a command or a flag, and change it in the same pull request.

## For a newcomer, in one screen

```text
havooch
├─ open  wait  ack  mark  reply  ask        get feedback: the listener's loop
├─ state  screenshot  help                   look and learn
├─ project    new add list
├─ app        status open quit home demo
├─ window     list new close resize
├─ control    take release
├─ player     load play pause seek mute unmute volume sound
├─ message    add edit delete send
├─ context    set
├─ thread     answer choose
├─ popover    open
├─ composer   set
├─ sidebar    show hide
├─ version    show find menu section
├─ compare    open find set swap start exit
├─ theme      list set
├─ config     path check close-notice
├─ setup      status link install cancel
├─ connect    pick disconnect forget
├─ tour       open next skip close
└─ first-run  open next back pick demo skip
```

Every command is `havooch <group> <verb>`, except the listener's loop and three utilities at the top. `havooch --help` shows the top help, `havooch <group>` a group's commands, and `havooch <group> <verb> --help` one command with examples. `havooch help --json` prints the whole table for an agent.

## 1. Requirements

### Callers

1. **The listener agent** receives the person's sends and answers on their threads. It is the main caller, and it learns the command from the havooch-mate skill and the help.
2. **An agent acting for the person** opens a video or a project for them.
3. **The operator agent** drives the UI under the lease, for checks, screenshots and the acceptance scripts.
4. **A person at a terminal** sets Havooch up and checks it.

### Jobs

1. A listener should be able to wait for a send, acknowledge it, mark each message's state, reply and ask on a thread.
2. An agent should be able to open a video for the person, make a project and add a version to it.
3. An operator should be able to do every UI action through a command that runs the same code as the click.
4. Anyone should be able to read the app's state and take a screenshot.
5. A person should be able to set Havooch up, check their settings and pick a theme.

### Roles

Each request has one role, in `ControlRequest.Role`. The help groups the commands by them.

| Role | Rule | Commands |
|---|---|---|
| free | changes nothing anyone sees; no lease | `state`, `app status`, `window list`, `theme list`, `setup status`, `control take`, `control release` |
| person | acts for the person, as their own click; no lease | `open`, `project new`, `project add` |
| listener | the agent that receives sends; no lease | `wait`, `ack`, `mark`, `reply`, `ask` |
| operator | drives the UI; needs the lease | every other command that reaches the app |

### Runtime

`help`, `--version`, `config path`, `config check` and `project list` need no app. `app status` answers without the app when it isn't running. `open`, `project new`, `project add` and `app open` launch the app when it isn't running. `wait` connects again while the app isn't running, until its timeout. Every other command needs the running app.

### Out of scope

Shell completions, colour, interactive prompts, and a schema of the `--json` shapes. Aliases for the old names: Havooch has no users who depend on them yet, so this design replaces the old names in one release.

## 2. Command model

### Nouns

Every group is a word from `GLOSSARY.md` or a part of the UI a person can see: `popover` is the comment popover, `composer` the sidebar's field, `sidebar` the sidebar's views. "Message" replaces "comment" everywhere, as the glossary asks.

### Verbs

One meaning each, on every group that has the action.

| Verb | Meaning | Used by |
|---|---|---|
| `list` | print many; changes nothing | `project`, `window`, `theme` |
| `status` | print the state of one thing; changes nothing | `app`, `setup` |
| `new` | make a new thing | `project`, `window` |
| `add` | put a thing into a parent | `project` (a version), `message` (on a thread) |
| `edit` / `delete` | change or remove an existing thing | `message` |
| `set` | change one value | `context`, `composer`, `theme`, `compare` |
| `open` / `close` | bring up or dismiss the app, a video, a window, a panel or a popover | `open`, `app`, `window`, `popover`, `compare`, `tour`, `first-run` |
| `show` / `hide` | put a view on screen or take it off | `sidebar`, `version` |
| `find` | open a search list with a query typed in | `version`, `compare` |
| `pick` | select a harness | `connect`, `first-run` |
| `choose` | answer with a quick-reply choice | `thread` |
| `start` / `exit` | enter or leave a mode | `compare` |
| `next` / `back` / `skip` | move through steps | `tour`, `first-run` |
| `load` | put a video in the player, paused, under the lease | `player` |

A panel inside a group opens with the group's verb and closes with `--close`: `player sound`, `version find`, `version menu`.

### Top level

Only the listener's loop (`open wait ack mark reply ask`), `state`, `screenshot` and `help`. An agent runs the loop in every session, so it stays short. Everything else lives in a group.

### Targets

- A window: `--window <id>`, else the key window. The table marks which commands take it, and the help prints that from the table.
- A thread: a word, its id or its number in the open video (`0` is General).
- A message or a send: a word, its id.
- A project: a word, its slug. A version: a word, its number (`3` or `v3`).

## 3. Inputs

Global options, on every command: `--json`, `-h` and `--help`. `--window <id>` on the commands that act on one window. `--version` on `havooch` alone. `--` ends the options, so a message's text can start with a dash.

Every wait takes `--timeout <seconds>`: `wait`, `ask` and `control take`. With no timeout, `wait` and `ask` wait with no limit, and `control take` fails at once when another agent holds the lease.

```text
open <path> [--project <slug>]
wait [--video <path> | --project <slug>] [--timeout <seconds>]
ack <send-id> [<text>]
mark <message-id> working|done|failed [<text>]
reply <thread> <text>
ask <thread> <question> [--choice <text>]... [--timeout <seconds>]
state
screenshot <abs.png> [--appearance light|dark] [--hide-agent-indicator] [--window main|settings|about|first-run|<id>]
help [<group> [<verb>]] [--json]

project new <slug> --from <path> [--title <title>]
project add <slug> <path> [--label <label>]
project list

app status
app open [--demo <folder>]
app quit
app home
app demo

window list
window new
window close [<id>]
window resize <width>

control take [--timeout <seconds>]
control release

player load <path>
player play
player pause
player seek <seconds|m:ss>
player mute
player unmute
player volume <0-100>
player sound [--close]

message add <text> [--at <time>] [--region x,y,w,h] [--thread <thread>]
message edit <message-id> <text>
message delete <message-id>
message send

context set <text>

thread answer <thread> <text>
thread choose <thread> <number>

popover open [<text>] [--region x,y,w,h]
popover open --thread <thread> [--frame x,y,w,h]

composer set [<text>] [--region x,y,w,h] [--general]

sidebar show [threads | thread <thread> | connect]
sidebar hide

version show <n>
version find [<query>] [--close]
version menu [--search <text>] [--close]
version section <n> [--remove]

compare open
compare find left|right [<query>]
compare set [--left <n>] [--right <n>] [--layout side-by-side|flip|slider] [--side left|right] [--slider <0-1>]
compare swap
compare start
compare exit

theme list
theme set <name|system>

config path
config check
config close-notice

setup status
setup link [--dry-run]
setup install [--harness <name>]... [--dry-run]
setup cancel

connect pick <harness>
connect disconnect
connect forget

tour open
tour next
tour skip
tour close

first-run open [welcome|tools|connect|try-it]
first-run next
first-run back
first-run pick <harness>
first-run demo
first-run skip
```

The words keep their natural order, target first and text last, so they stay words. `popover open --thread` takes neither `<text>` nor `--region`.

## 4. Output and errors

- What each command prints, plain and with `--json`, is the table in `docs/low-level-design.md` under ReviewCommand. The redesign keeps every output and every JSON shape, and changes only the command names inside them.
- Data goes to standard output. A refusal goes to standard error as one line that names the command that fixes it, such as `no video is open in the window; load one with havooch player load <path>`.
- Exit codes:

| Code | Meaning |
|---|---|
| 0 | done |
| 1 | refused or failed |
| 2 | wrong usage |
| 124 | a wait ran out: `wait --timeout`, `ask --timeout`, `control take --timeout` |

Wrong usage prints the command's usage line and `run havooch <group> <verb> --help for details`. An unknown command prints the closest command, if one is near, and the top help's usage line.

## 5. Help

The help is generated from the command table, so it can't list something the code doesn't have.

### The top help

`havooch --help`, `havooch -h`, `havooch help` and `havooch` alone print it, and exit 0.

```text
Havooch: a video player for giving feedback to agents.

Usage: havooch <command> [options]
       havooch <group> <verb> [options]

Get feedback:
  open <path>               open a video for the person, playing
  wait                      wait for the person's next send and print it
  ack <send-id> [<text>]    say you have a send
  mark <message-id> <state> say a message is working, done or failed
  reply <thread> <text>     send a message on a thread
  ask <thread> <question>   ask a question and print the answer
  project                   make projects and add versions to them

Look:
  state                     everything the app shows
  screenshot <abs.png>      save a window as a PNG

Drive the app (take the lease first: havooch control take):
  app        start, quit and check the app
  window     list, open, close and resize windows
  control    take and release the lease
  player     load, play, seek and set the sound
  message    queue, edit, delete and send messages
  context    set the open video's context note
  thread     answer the agent on a thread
  popover    open the comment popover
  composer   write in the sidebar's composer
  sidebar    show the sidebar's views
  version    show and find a project's versions
  compare    compare two versions
  theme      list and set themes
  config     find and check config.toml
  setup      link the command and install the skill
  connect    pick, disconnect and forget an agent
  tour       step through the setup tour
  first-run  step through the first-run window

Options:
  --json          print JSON
  --window <id>   act on that window, not the key one
  -h, --help      show help: havooch <group> --help, havooch <group> <verb> --help
  --version       print the version

Environment:
  HAVOOCH_SUPPORT_DIR   use this data folder, not yours
  HAVOOCH_MUTED=1       play no sound in any window

Exit codes: 0 done, 1 refused or failed, 2 wrong usage, 124 a wait ran out.

Guide: https://github.com/yahyabedirhan/havooch/blob/main/docs/guide.md
Agents: havooch help --json prints every command. havooch setup install installs the havooch-mate skill.
```

### A group's help

`havooch <group> --help`, `havooch help <group>` and `havooch <group>` alone print it, and exit 0. Each command gets its full usage line and its summary under it. An operator group says it needs the lease, and the `--window` line appears only when the group's commands take it.

```text
Load, play, seek and set the sound. Needs the lease: havooch control take.

Usage: havooch player <verb> [options]

Commands:
  havooch player load <path>
      load a video file, paused at its start
  havooch player seek <seconds|m:ss>
      move to an exact time
  ...

Options: --window <id>, --json
Run havooch player <verb> --help for a command's details.
```

### A command's help

`havooch <group> <verb> --help` and `havooch help <group> <verb>` print it, and exit 0. `-h` or `--help` counts when it comes right after the command's name; write `--` before a text that is `--help`.

```text
Move to an exact time.

Usage: havooch player seek <seconds|m:ss> [--window <id>] [--json]

Examples:
  havooch player seek 12.5
  havooch player seek 1:05 --window w2

The player pauses on that frame. Needs the lease.

Exit codes: 1 when no video is open or the time is past the end.
```

### Summaries

One line, starting with a verb, saying what the command achieves. The UI action that a command matches goes in its description, not in its summary.

## 6. Implementation

```text
Sources/ReviewCommand/
  HavoochCLI.swift        one path: read the globals, find the command, parse, run, print, exit
  CommandTable.swift      Command, CommandGroup, Arguments, Invocation; the groups in help order
  Help.swift              the top, group and command help, and help --json, all from the table
  <Group>Commands.swift   one file per group: AppCommands, WindowCommands, ControlCommands,
                          PlayerCommands, MessageCommands, ContextCommands, ThreadCommands,
                          PopoverCommands, ComposerCommands, SidebarCommands, VersionCommands,
                          CompareCommands, ThemeCommands, ConfigCommands, SetupCommands,
                          ConnectCommands, TourCommands, FirstRunCommands, ProjectCommands
  ListenerCommands.swift  open wait ack mark reply ask
  LookCommands.swift      state screenshot
```

`Command` holds the name, usage, summary, description, examples, the role, the options, `takesWindow` and the parse function. `CommandGroup` holds the group's name, summary, help section and commands.

Contract tests:

- Every example in the table parses, and its request has the command's role.
- Every `havooch <words>` in `Sources`, `docs`, `scripts`, `site` and the havooch-mate skill names a command in the table.
- The top help and one group's help match stored snapshots.

## 7. Evolution

| Change | What you touch |
|---|---|
| A new command | one `Command` in its group's file, a `ControlRequest` case and its role, the guide |
| A new group | one file, one line in the group list, this document's tree |
| A rename | the table and this document; the contract test finds every caller in the docs, the scripts and the skill |
| A new `--json` field | the output only; existing fields keep their names |
| A wait | `--timeout <seconds>` and exit 124 |

Breaking changes ship with a minor version before 1.0, with the guide, the site and the havooch-mate skill in the same release.

## Changes from 0.5.1

| 0.5.1 | Now | Why |
|---|---|---|
| `status <message-id> …` | `mark <message-id> …` | `status` reads as `app status`; the glossary avoids "status" for a message's state |
| `player open <path>` | `player load <path>` | `open` opens a video playing for the person |
| `comment add`, `comment edit`, `comment delete` | `message add`, `message edit`, `message delete` | the glossary's word is "message" |
| `send` | `message send` | it sends the queued messages |
| `comment open` | `popover open` | it opens the comment popover |
| `thread open <thread> [--frame]` | `popover open --thread <thread> [--frame]` | the same popover |
| `comment compose` | `composer set` | it writes in the composer |
| `thread show <thread>` | `sidebar show thread <thread>` | a sidebar view |
| `thread list` | `sidebar show threads` | a sidebar view; `list` prints |
| `connect show` | `sidebar show connect` | a sidebar view |
| `thread versions [--search] [--close]` | `version menu [--search] [--close]` | it is about versions |
| `thread version <n> [--remove]` | `version section <n> [--remove]` | it is about versions |
| `version pick [<query>]`, `version close` | `version find [<query>]`, `version find --close` | `pick` selects a harness |
| `compare pick <side> [<query>]` | `compare find <side> [<query>]` | the same reason |
| `tour show` | `tour open` | a panel opens |
| `first-run show [<step>]` | `first-run open [<step>]` | a window opens |
| `config dismiss` | `config close-notice` | a panel closes |
| `control take --wait`, `ask --wait` | `--timeout` | every wait takes the same flag |
| exit 2 for a timeout, 64 for wrong usage | 124 and 2 | the common codes |
| one flat help | the top, group and command help, `help --json` | the help shows the tree |
