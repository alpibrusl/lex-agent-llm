# lex-agent-llm

**Part of the [Lex](https://lexlang.org) project** — Library · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

> The brain↔skin bridge: run a `lex-llm` agent loop as a `lex-agent` Skill, reachable over A2A + MCP.

## Why

There are two `AgentDef`s, and they are different layers:

- **`lex-llm/agent.AgentDef`** — the **brain**: a model + tools + `run_loop`.
- **`lex-agent/server.AgentDef`** — the **skin**: a capability reachable over A2A / MCP.

They're orthogonal and stay independent (neither imports the other). The only place they meet is a Skill's `handle`, where a brain runs. That glue was being copy-pasted in every agent (`lex-soft`'s runner, `lex-oms-agent`, `lex-code`'s chat). This package names it once, so the mapping from a `run_loop`'s Steps to a Skill outcome can't drift.

## Use

```lex
import "lex-agent-llm/src/bridge" as bridge
import "lex-agent/src/server" as srv
import "lex-mcp/src/compose" as compose

# brain: a lex-llm AgentDef (model + tools); cap: a lex-spec Capability
let skill := bridge.skill_of_loop(cap, brain)
let agent := srv.make_agent_def(card, [skill])
compose.serve_both(agent, 4040)   # now A2A (/) + MCP (/mcp), one source of truth
```

Three layers, pick what you need:

- `collect(steps) -> LoopOut` — the pure, duplicated bit: final assistant text + executed tool names.
- `outcome_of_steps(steps) -> HandlerOutcome` — `collect`, shaped as a lex-agent outcome. Hosts that run the loop their own way (e.g. `lex-soft`'s per-turn subprocess) use **this** for the mapping only.
- `skill_of_loop(cap, brain) -> Skill` — the convenience: a Skill whose handle runs the brain in-process.

Invocation policy stays with the host: `skill_of_loop` runs in-process; a host that wants isolation keeps its own invocation and calls `outcome_of_steps`.

Type-check and test:

```sh
lex ci
```
