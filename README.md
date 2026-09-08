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
`pi: ,thinking high`); bare `,command` lines work in `#pi` and DMs.

| Command | Effect |
| --- | --- |
| `,model [query]` | Show the current and available models, or select the first one matching the query (provider/id/name, case-insensitive). |
| `,thinking [level]` | Set the thinking level (`off`…`max`); no level cycles. |
| `,compact [instructions]` | Compact the channel's session context. |
| `,reload` | Reload the session's plugins. |
| `,join #a,#b` | Join channels, one new session each (a remembered session is reused). |
| `,fork #chan [#from]` | Join `#chan` with a session forked from `#from` (default: this channel): conversation, files, and heap are copied. |
| `,part #chan` | Leave a channel; its session is kept for the next `,join`. |
| `,sessions` | List channel → session. |
| `,help` | Command reference. |

## Run locally

```
cp .env.example .env    # set ANTHROPIC_API_KEY (or a custom provider, see below)
docker compose up --build
```

This starts an [Ergo](https://github.com/ergochat/ergo) IRC server on
`localhost:6667`, a dedicated mcp-js engine, and the bot. Connect any IRC client
to `localhost:6667`, join `#pi`, and say `pi: hello`. The browser UI for
watching channels is at `http://127.0.0.1:8600/?token=<PI_WEB_TOKEN>`.

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
| `PI_WEB_PORT`, `PI_WEB_TOKEN` | off | serve the `pi web` browser UI on the same sessions |
| `PI_IRC_STATE_DIR` | `/data/agent/irc` | channel → session map (`channels.json`) |

Sessions, the channel map, and the engine's heaps and snapshots live under
`/data` in both containers; keep those on volumes.

## Railway

The image runs as-is on Railway. One service for this repo (Dockerfile build,
volume at `/data/agent`) and one dedicated mcp-js service from the
`wholelottahoopla/mcp-js:0.21.0-rc.2` image (0.21 or newer: the session file endpoints the pi coordinator uses shipped in mcp-js #267) with

```
--http-port=3000 --heap-store=dir --heap-dir=/data/heaps --fs-store=dir --session-db-path=/data/sessions
```

and a volume at `/data`. Point `MCP_JS_URL` at the mcp-js service's private
domain (`http://<service>.railway.internal:3000`) and `IRC_SERVER` at your IRC
server's private domain. Provider keys can be Railway variable references to
another service that already holds them.

## How it works

`pi irc` is an experimental presentation in the pi fork
(`packages/coding-agent/src/experimental/irc/`, see its
[docs](https://github.com/r33drichards/pi/blob/main/packages/coding-agent/docs/experimental-irc.md)).
It runs pi's experimental server in-process; each channel holds one client
connection attached to its session and relays transcript events back to IRC.
`,fork` uses `SessionManagement.fork` for the conversation and seeds the new
mcp-js session from the source's latest heap and filesystem ids over the
coordinator's `/api/exec`. The Dockerfile pins the pi commit in `PI_COMMIT`.
