# lex-agent-llm — the brain↔skin bridge
#
# Two AgentDefs meet here, and ONLY here:
#   • lex-llm/agent.AgentLoop  — the BRAIN: a model + tools + run_loop.
#   • lex-agent/server.AgentDef — the SKIN: a capability reachable over A2A / MCP.
#
# lex-llm and lex-agent stay independent (neither imports the other). The glue —
# "run this lex-llm loop as a lex-agent Skill" — was being copy-pasted in every
# agent (lex-soft's runner, lex-oms-agent, lex-code's chat). This package names it
# once so "expose an LLM agent over A2A + MCP" is a one-liner, and the mapping
# from a run_loop's Steps to a Skill outcome can't drift between agents.
#
# Layers:
#   collect(steps)            — the pure, duplicated bit: final assistant text +
#                               the tool names that were executed.
#   outcome_of_steps(steps)   — collect, shaped as a lex-agent HandlerOutcome
#                               (completed + a reply message). Hosts that run the
#                               loop their own way (e.g. lex-soft's per-turn
#                               subprocess) use THIS for the mapping only.
#   skill_of_loop(cap, brain) — the convenience: a Skill whose handle runs the
#                               brain in-process and returns outcome_of_steps.
#                               For the simple case (lex-oms-agent, lex-code).
#
# Invocation policy stays with the host: skill_of_loop runs in-process; a host
# that wants isolation keeps its own invocation and calls outcome_of_steps.
#
# Effects: collect/outcome_of_steps are pure; the skill_of_loop handle carries
# the Skill handler row (the brain's run_loop touches net, llm, io, proc).

import "std.list" as list

import "std.iter" as iter

import "lex-llm/src/delta" as d

import "lex-llm/src/message" as lmsg

import "lex-llm/src/agent" as ag

import "lex-agent/src/server" as srv

import "lex-agent/src/message" as amsg

import "lex-agent/src/task" as tk

import "lex-spec/capability" as cap

# What a run actually produced: the final assistant text and the tool names that
# were executed along the way (order preserved). Mirrors lex-soft's LoopOut so it
# can adopt this without behaviour change.
type LoopOut = { text :: Str, tools :: List[Str] }

# Fold a run_loop's Steps into a LoopOut. StepDone carries the final lex-llm
# message (text via lmsg.content); StepToolExec records a tool invocation.
# StepDelta / StepToolResult don't change the outcome and are ignored.
fn collect(steps :: List[d.Step]) -> LoopOut {
  list.fold(steps, { text: "", tools: [] }, fn (acc :: LoopOut, st :: d.Step) -> LoopOut {
    match st {
      StepDone(m) => { text: lmsg.content(m), tools: acc.tools },
      StepToolExec(name, _id) => { text: acc.text, tools: list.concat(acc.tools, [name]) },
      _ => acc,
    }
  })
}

# Map a finished run_loop to a lex-agent Skill outcome: completed, with the final
# text as the agent's reply. No artifacts — a host that produces domain artifacts
# (e.g. lex-oms-agent's blotter/positions/risk) keeps its own handler.
fn outcome_of_steps(steps :: List[d.Step]) -> srv.HandlerOutcome {
  let out := collect(steps)
  { next_state: TSCompleted, reply: Some(amsg.agent_text(out.text)), artifacts: [] }
}

# First text part of an inbound lex-agent message (the user's turn).
fn first_text(parts :: List[amsg.Part]) -> Str {
  match list.head(parts) {
    Some(TextPart(s)) => s,
    _ => "",
  }
}

# The one-liner: turn a lex-llm brain into a lex-agent Skill for `capability`.
# The handle takes the inbound message's text as the user turn, runs the brain's
# loop in-process, and returns the mapped outcome. Compose into an AgentDef and
# serve over A2A + MCP with lex-mcp's serve_both (or a router /mcp route).
fn skill_of_loop(capability :: cap.Capability, brain :: ag.AgentLoop) -> srv.Skill {
  { capability: capability, handle: fn (m :: amsg.Message) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] srv.HandlerOutcome {
    let conv := [UserMsg(first_text(m.parts))]
    outcome_of_steps(iter.to_list(ag.run_loop(brain, conv)))
  } }
}

