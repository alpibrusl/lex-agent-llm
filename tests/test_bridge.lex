# lex-agent-llm — bridge tests
#
# Exercises the pure mapping (collect / outcome_of_steps) with synthetic Steps —
# no provider, no network. The run_loop wiring in skill_of_loop is covered by the
# consumers' own end-to-end tests (it just calls lex-llm's run_loop).
#
#   lex test tests/

import "std.list" as list

import "lex-agent/src/message" as amsg

import "../src/bridge" as bridge

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

# collect: the final StepDone text wins; earlier StepToolExec names accumulate
# in order; deltas/tool-results are ignored.
fn test_collect_final_text_and_tools() -> Result[Unit, Str] {
  let steps := [StepToolExec("search", "id1"), StepToolExec("fetch", "id2"), StepDone(AssistantMsg("the answer", []))]
  let out := bridge.collect(steps)
  match check("text is final assistant content", out.text == "the answer") {
    Err(e) => Err(e),
    Ok(_) => check("tools captured in order", out.tools == ["search", "fetch"]),
  }
}

# No StepDone → empty text (an unfinished/empty loop), no tools.
fn test_collect_empty() -> Result[Unit, Str] {
  let out := bridge.collect([])
  match check("empty text", out.text == "") {
    Err(e) => Err(e),
    Ok(_) => check("no tools", list.len(out.tools) == 0),
  }
}

# outcome_of_steps: completed, with the final text as the reply message.
fn test_outcome_completed_with_reply() -> Result[Unit, Str] {
  let oc := bridge.outcome_of_steps([StepDone(AssistantMsg("hi there", []))])
  let state_ok := match oc.next_state {
    TSCompleted => true,
    _ => false,
  }
  match check("state is completed", state_ok) {
    Err(e) => Err(e),
    Ok(_) => match oc.reply {
      None => Err("expected a reply message"),
      Some(m) => check("reply text is the final content", bridge.first_text(m.parts) == "hi there"),
    },
  }
}

# outcome carries no artifacts (domain artifacts stay in the host's handler).
fn test_outcome_no_artifacts() -> Result[Unit, Str] {
  let oc := bridge.outcome_of_steps([StepDone(AssistantMsg("x", []))])
  check("no artifacts", list.len(oc.artifacts) == 0)
}

fn run_all() -> Int {
  let results := [test_collect_final_text_and_tools(), test_collect_empty(), test_outcome_completed_with_reply(), test_outcome_no_artifacts()]
  list.fold(results, 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

