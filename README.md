# pi-irc

The [pi](https://github.com/r33drichards/pi) coding agent as an IRC bot. Every
IRC channel the bot is in is its own pi session, and every session is an
[mcp-js](https://github.com/r33drichards/mcp-js) sandbox: the agent has
`read`, `write`, and `run_js` on a per-channel filesystem snapshot with a
persistent V8 heap, and no access to the host.

The bot joins `#pi` by default. That is the control channel: talk to it there,
or tell it to `,join` other channels, each with a fresh session, or `,fork` a
channel from the current one so the new channel starts with the same
conversation, files, and heap.

## Talking to it

The bot only reacts to channel lines that mention its nick (`pi: …`, `pi, …`,
`@pi …`, or `pi` anywhere in the line, case-insensitive on whole words), and to
DMs. Unmentioned chatter is never a prompt. Each mention is a prompt to that
channel's session. While a turn runs, more
lines are delivered as steering. The bot replies with the model's messages
and one line per tool call:

```
<rob> pi: use run_js to write /hello.txt with 'hi' and read it back
<pi>  [run_js] 1 line: await fs.writeFile('/hello.txt', 'hi');
<pi>  [run_js] → (no output)
<pi>  [read] /hello.txt
<pi>  [read] → hi
<pi>  `/hello.txt` contains: `hi`
```

## Commands

Comma-prefixed. Inside a mention they work in any channel (`pi ,model astra`,
`pi ,fork ptest2`); bare `,command` lines work in `#pi` and DMs. Channel
names may omit the `#`.

| Command | Effect |
| --- | --- |
| `,model [query]` | Show the current and available models, or select the first one matching the query (provider/id/name, case-insensitive). |
| `,thinking [level]` | Set the thinking level (`off`…`max`); no level cycles. |
| `,compact [instructions]` | Compact the channel's session context. |
| `,reload` | Reload the session's plugins. |
| `,join #a,#b` | Join channels, one new session each (a remembered session is reused). |
| `,fork [#a,#b]` | Fork the channel you typed in into each channel (conversation and files are copied) and join them. `#` is optional: `pi ,fork ptest2,ptest3`. With no channel, `pi ,fork` creates `#<channel>-<petname>` (for example `#clone-brave-otter`) for you. |
| `,part #chan` | Leave a channel; its session is kept for the next `,join`. |
| `,merge #child [ours\|theirs]` | Merge a forked child's files back into this channel (three-way from the fork point via mcp-js `/api/fs/merge`). Conflicting paths are reported; `ours`/`theirs` resolves them. |
| `,sessions` | List channel → session. |
| `,help` | Command reference. |

## Delegation

The model in any channel can delegate: `spawn_channel` forks the channel into
`#<channel>-<petname>`, runs a prompt there as the child's own turn (visible in
the child channel), waits, and returns the child's answer; `merge_channel`
brings the child's files back (same as `,merge`); `irc_send` posts to another
channel, and a mention in that text prompts the other channel's session.

```
<rob> pi: spawn a child to create /notes/plan.md with a 3-line plan and report back
<pi>  [spawn_channel] create /notes/plan.md with a 3-line plan …
<pi>  spawned #pi-brave-otter (session 01a0…; files and conversation carried over)
<pi>  [spawn_channel] → Child #pi-brave-otter (session 01a0…) finished. (+3 lines)
<pi>  1. …  2. …  3. …
<rob> pi ,merge #pi-brave-otter
<pi>  merged #pi-brave-otter into #pi: files are live (snapshot dc70fb1f3443)
```

## Run locally

```
cp .env.example .env    # set ANTHROPIC_API_KEY (or a custom provider, see below)
docker compose up --build
```

This starts an [Ergo](https://github.com/ergochat/ergo) IRC server on
`localhost:6667`, a dedicated mcp-js engine, and the bot. Connect any IRC client
to `localhost:6667`, join `#pi`, and say `pi: hello`. 
## Configuration

Everything is environment variables; the container writes pi's settings from
them at start. Mount a directory at `/config` with `settings.json` and
`models.json` to override (see `config/*.example.json`).

| Variable | Default | Meaning |
| --- | --- | --- |
| `MCP_JS_URL` | required | mcp-js coordinator, e.g. `http://mcp-js:3000`. Must have heap and fs stores enabled. |
| `IRC_SERVER` | required | IRC host |
| `IRC_PORT` | `6667` (`6697` with TLS) | |
| `IRC_TLS` | `false` | |
| `IRC_NICK` | `pi` | |
| `IRC_PASSWORD` | | server password (`PASS`) |
| `IRC_CHANNELS` | `#pi` | channels to join at start, comma separated |
| `IRC_CONTROL_CHANNEL` | `#pi` | where `,join`/`,fork`/`,part` are accepted (DMs always are) |
| `IRC_RESPOND_TO_ALL` | `false` | opt-in: react to every channel line instead of mentions only |
| `PI_DEFAULT_PROVIDER`, `PI_DEFAULT_MODEL` | `anthropic`, `claude-sonnet-5` | model for new sessions |
| `PI_MODELS_JSON` | | contents of a pi `models.json` for custom providers (e.g. a LiteLLM gateway) |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, … | | provider credentials, as pi expects them |
| `PI_IRC_STATE_DIR` | `/data/agent/irc` | channel → session map (`channels.json`) |

Sessions, the channel map, and the engine's heaps and snapshots live under
`/data` in both containers; keep those on volumes.

## The engine: `mcp-js/`

The dedicated mcp-js coordinator is configured by one file,
[`mcp-js/config.toml`](mcp-js/config.toml), loaded with `MCP_V8_CONFIG`
(every key is a `mcp-v8` flag; see the mcp-js
[config file reference](https://github.com/r33drichards/mcp-js/blob/main/site-docs/reference/config-file.md)),
plus the Rego policies it references:

- `fs_store = "dir"` and `session_db_path`: per-session filesystem snapshots.
- `allow_external_modules = true` with `policies/modules.rego`: `import()`
  of ES modules from esm.sh, jsdelivr, and unpkg.
- `policies/fetch.rego`: `fetch` to GitHub (github.com, api/codeload/raw/objects)
  and the same CDNs, nothing else.
- `heap_memory_max = 6144`, `execution_timeout = 300`: a depth-1
  isomorphic-git clone of a 150 MiB pack (for example trycua/cua) peaks near
  6 GB and takes about 90 s; 300 s is the server maximum.
- `heap_store = "none"`: heap persistence is off. With module imports and
  large fetches in play, serializing the V8 heap after a run can abort the
  whole engine (V8 "Unknown external reference"; reproduced with the
  trycua/cua clone). Files persist per session; `globalThis` does not, and
  the `run_js` tool description tells the model so.

Locally, compose mounts `mcp-js/` at `/config` read-only. On Railway the
engine is built from `mcp-js/Dockerfile` (`FROM wholelottahoopla/mcp-js`,
`COPY mcp-js/ /config/`, `ENV MCP_V8_CONFIG`) so the same files ship in the
image. Give the engine service at least 7 GB of memory.

With network and modules enabled, sessions can clone repositories:

```
<rob> pi clone https://github.com/trycua/cua (depth 1) and list the top-level files
<pi>  [run_js] 4 lines: const git = (await import("https://esm.sh/isomorphic-git@1.27.1")).default;
<pi>  [run_js] → AGENTS.md, CITATION.cff, CLAUDE.md, … (+1 lines)
```

`MCP_JS_NETWORK` / `MCP_JS_MODULES` (default `true`) tell pi what the engine
allows, which is how the model learns that `fetch` and `import()` work.

## Railway

Two services from this repo, plus the project's IRC server:

- `pi-irc-engine`: service setting "Dockerfile path" = `mcp-js/Dockerfile`
  (root directory `/`, watch paths `mcp-js/**`), volume at `/data`, variable
  `RAILWAY_RUN_UID=0` (Railway mounts volumes as root; the image runs as
  `mcpuser`). Everything else comes from `mcp-js/config.toml`. Do not add a
  root `railway.json`: it would override the Dockerfile path for every service
  built from this repo (and config-as-code is deprecated on Railway).
- `pi-irc`: the root `Dockerfile`, volume at `/data/agent`, and the variables
  from the table above. `MCP_JS_URL` is
  `http://${{pi-irc-engine.RAILWAY_PRIVATE_DOMAIN}}:3000`, `IRC_SERVER` the
  IRC service's private domain, and provider keys can be Railway variable
  references to a service that already holds them.

## Extensions

Sessions load whatever is installed in the agent directory, so the pi package
registry works from a channel. The image bakes in the packages listed in the
`PI_EXTENSIONS` build argument (default `npm:pi-schedule-prompt`) and copies
them into `/data/agent` on first boot; the volume keeps anything installed
later. To change the set, rebuild with

    docker build --build-arg PI_EXTENSIONS="npm:pi-schedule-prompt npm:pi-memory" .

Extensions that register slash commands or TUI widgets load without error, but
those surfaces are inert here: the bot has no terminal UI. `,reload` reloads
them.

Output an extension produces on its own, such as a scheduled prompt's answer,
reaches IRC only when the bot has a single channel open. With more than one,
the job runs and records success but its answer never arrives. Tools an
extension adds, such as `schedule_prompt` itself, work in every channel. See
the caveat below.

## How it works

`pi irc` lives in the pi fork (`packages/coding-agent/src/irc/`, see its
[docs](https://github.com/r33drichards/pi/blob/main/packages/coding-agent/docs/irc.md)).
Each channel owns a normal pi `AgentSession` running in the bot's process,
with pi's host file tools replaced by `read`/`write`/`run_js` over that
channel's own mcp-js filesystem snapshot. `,fork` copies the conversation with
`SessionManager.forkFrom` and seeds the new mcp-js session from the source's
latest filesystem id over the coordinator's `/api/exec`; `,merge` reconciles
them through `/api/fs/merge`. Every channel gets its own working directory
under the agent directory, because extensions keep project-local state there.
The Dockerfile pins the pi commit in `PI_COMMIT`.

One caveat comes with that runtime: it expects a single session per process,
and this bot runs one per channel. Two consequences:

- **Extension-driven turns only reach IRC when one channel is open.** With a
  single channel a scheduled prompt fires, the model answers, and the answer
  appears in the channel. With two, the job still executes and records
  `runCount: 1, lastStatus: success`, but the answer never arrives. Prompts
  typed by a person keep working either way.
- **A background timer in an extension can throw against a stale context.**
  `pi irc` names the channel that armed the timer, logs the failure, and keeps
  running instead of exiting. It does not dispose the session: disposing one
  invalidates the extension runtime the whole process shares and would stop
  every other channel.

The fix for both is one process per channel, matching what the runtime
assumes. Until then, run a single channel if you depend on scheduled prompts
reaching it.
