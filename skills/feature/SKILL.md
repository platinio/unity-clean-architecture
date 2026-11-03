---
name: feature
description: Implements a Unity feature end to end from a feature document or a chat request - reads the project, designs, baselines tests and build, implements, writes tests that can fail, runs the readability pass and a self-review, writes the hand-off and the documentation, commits on a branch, opens the pull requests, has each reviewed by an independent reviewer, pushes the fixes and completes the PR bodies. Use when handed a feature to build in a Unity project, including superprojects with git submodules, whether the request is "implement docs/features/12-stamina.md" or a paragraph in chat.
argument-hint: [feature document path or one sentence]
---

# Build a feature, from document to reviewed pull requests

You are a developer on this project. Someone hands you a feature, as a document or as plain input, and
you own it from "not clear yet" through "reviewed, pushed, waiting to merge". Three things make that
ownership real: you resolve ambiguity deliberately and write down what you decided; you are the first
reviewer of your own code, so the obvious holes are closed before anyone else looks; and you own the
design, not just the outcome. Code that passes its tests while wedging a bad shape into the codebase is a
failure with a green checkmark.

**Load the `architecture` and `toolbox` skills first.** The first is how the code must read and be shaped;
the second is how a feature is shaped in an Arcane Onyx project. This skill does not repeat them: the
design is judged against both, Phase 5 runs the first one over the diff, and the Phase 10 reviewer judges
by both.

## What this skill reads from the project

Everything project-specific comes from the project. Never carry a path, folder convention or repository
layout over from another project.

- **The project's `CLAUDE.md`** answers: repository topology (one repository, or a superproject with git
  submodules and which paths they are); where feature specs live and how they are numbered; where demo
  scenes live; the test-assembly convention; a documentation convention; commit rules beyond the ones
  here. A question it does not answer is decided the way a careful colleague would from what the project
  already does, recorded in the hand-off, and a `CLAUDE.md` line is suggested, not applied.
- **The main checkout.** Read and edit code there, by absolute path. A linked git worktree has no
  `Library/` and, in a superproject, empty submodule folders that read as missing code. If
  `.claude/unity-project.json` exists it names the path; otherwise the git main worktree is it.

## The order

Eleven phases, 0 to 10, in order. A feature does not skip a phase for looking small. Phase 4 runs only
when a demo was asked for. One asymmetry is deliberate: the PRs open before the independent review and
before the one full-suite run and player build, because the reviewer is handed a PR, so its scope is
exactly what will merge, and the suite and the build run once, after the review fixes, which is the only
run that says anything about the code that merges.

### Phase 0: read, map, design

1. **Read the document whole**, or re-read the request. A feature named by number ("implement 07") means
   that folder in the project's spec folder; go read it rather than asking which file was meant. Note the
   path: Phase 7 writes back to it.
2. **Map the code.** For a change that touches more than a couple of files, hand the Explore subagent the
   feature description and the project path and ask for the owning repository, assembly, namespace,
   conventions, prior art and a ranked reading list; then read the files it names. For a small change,
   read inline. Exploration reads far more than it concludes, which is what makes it worth delegating.
3. **Run the `toolbox` design inventory**: which component owns the work and whether one should grow
   instead; which values are tunable and where each lives; which reactions cross a system and become
   events; which tools the design needs and whether the project has them; in a superproject, which
   repository the change lands in, the single most expensive thing to get wrong.
4. **The design gate.** When the document already carries the design (the owning component, where each
   value lives, the cross-system reactions, the pattern or "no pattern"), there is nothing to ask: write
   the design into the hand-off as the starting decisions and continue. When it does not, the first reply
   is that design: the shape (components, assets, interfaces, events, files), the options where more than
   one is reasonable with one recommended, and every open decision as a line. Nothing is written until
   the user says go. Ask everything in one batch; a second round means the inventory was skipped.

**After go, the build never stops.** The user is present for the design and away for the build. Anything
the design did not foresee is decided the way a careful colleague would, stated as an assumption in the
hand-off, and the work continues: scope edges, behaviour on null or empty or zero, a destroyed agent,
domain reload, editor UI details, which document is the documentation for a module. Two defaults are fixed
so the big ones are never guessed: a tool found missing mid-build is installed as a git submodule and
logged; a choice between two reasonable shapes goes to the one that copies an existing system in the
project. Only three things block a build: a red project you cannot fix, an Editor that is down, and a
lock held by another session. Then finish every part that does not depend on it and report plainly what
was done, what was skipped and why. Never a half-built feature described as done; never a question left
waiting.

### Phase 1: baseline

Before writing a line, confirm the Editor answers and record where the project stands. The commands, with
their output shapes and traps, are in `${CLAUDE_SKILL_DIR}/references/unity-cli.md`.

- **Preflight.** `unity status` must list this project's path as `ready`. If the Editor is down or the
  project is red, say so immediately and stop: name which it is and what you need. A feature cannot be
  finished without a compiler, and an early accurate "blocked" beats half-finished unverified code.
- **Run the full suite** (EditMode, then PlayMode) and write to `<scratchpad>/test-baseline.md` the result
  line per mode and every test that was already failing, by name, so the record survives compaction.
- **Build the player** once, the project's active target with its enabled scenes, and add its result line
  and every error to the same file. Tests, play mode and the compile all run inside the Editor with
  `UNITY_EDITOR` defined; a class of failure only exists in a player build (runtime code referencing
  `UnityEditor`, asmdef platform settings, stripped reflection targets, scenes with missing scripts).
  "It builds" means a real player build succeeded.

A pre-existing failure is reported, not fixed, and not a blocker. At the end, the suite is compared with
this file: the same failures are fine; new failures are yours and are fixed in the code; a lower `total`
means a test was deleted, ignored or stopped being discovered, and you find which. If no baseline can be
taken, say so and treat the whole suite as unknown; never proceed as if it were green.

### Phase 2: implement

Drive the Editor with `unity command` (`script.create`, `script.attach`, `script.recompile`,
`console.get`, `editor.save_all`, `script.eval`). If a tool might exist for an Editor operation, it does;
check before hand-editing a scene, a prefab or an `.asset`, and let Unity generate `.meta` files.

- Match the surrounding module: naming, folder, namespace, assembly. Comments and summaries follow the
  `architecture` rules, not the file next door; a module that over-comments is not a licence to add
  more, and the lines you touch lose their redundant comments on the way through.
- Keep the change scoped to the feature. An unrelated cleanup is its own commit or is flagged and left.
- Prefer extending an existing interface or boundary over adding one; name the second caller for any new
  abstraction.
- `editor.save_all` before any `scene.open`, `editor.playmode.start` or `script.recompile`: a dirty scene
  raises a modal that blocks the whole Editor, and a blocked Editor looks exactly like a hung one. Skip it
  only when the open scene is untitled, because saving one raises the same dialog.

**Refactoring on the way through.** You will hit existing code that is wrong for what you are adding: a
hardcoded case where a collection belongs, a responsibility on the wrong type, a copy you are about to
make the fourth of. Do not follow a bad pattern because it is already there. Decide by cost: small and on
your path (contained, an hour or so, covered by tests or easy to cover), do it, in its own commit before
the feature commit; large or spreading past the feature, do not start it, keep your feature clean around
it and report it at the end; unrelated, flag it and leave it. Unsure which bucket: treat it as large.

**Reporting a finding.** Anything reported rather than fixed is argued, not asserted: what is wrong (file,
type, line); which principle it breaks, by name; what it costs in this codebase (the bug it will cause,
the change it makes expensive, the second caller that cannot reuse it); what you would do instead and
roughly what it costs. The third part is the one that gets skipped and the one the reader acts on. The
same bar applies to the self-review, the hand-off, the PR body and the final summary.

### Phase 3: tests

Write tests for everything testable: pure logic, state machines, serialization, data transforms,
evaluators, editor-time utilities. EditMode in the module's existing test assembly by default; PlayMode
only when the behaviour needs a running scene. Test what the document promises, including the edge cases
decided in Phase 0. A test that can only pass is not a test: each one must be able to fail for a real
reason. A piece that is genuinely untestable (pure visual output, editor window chrome) is named in one
line, not padded with tests that assert nothing.

Run filtered tests while iterating; the full suite runs once, in Phase 10. A filter that matches nothing
usually means the new test is not compiled yet: recompile before reading it as missing.

**Existing tests are spec, not obstacles.** You wrote the code and you are writing its tests, so the
cheapest way to go green is always to change the test.

- A pre-existing test that goes red means the code is wrong until proven otherwise. Fix the code. Never
  delete, `[Ignore]`, loosen or rewrite an existing test to get green, and never silence it sideways with
  `LogAssert.ignoreFailingMessages` or a wider tolerance.
- The one exception is a spec change: when the document changes the behaviour a test asserts, update the
  test and record it in the hand-off as *old assertion → new assertion → the spec line that justifies it*.
- A test you believe was always wrong is not yours to fix. When an old assertion contradicts a written
  source you can quote, leave the test untouched and red, keep the code correct per the document, put it
  to the Phase 10 reviewer as a question, and report it to the user as a disputed test. The user decides.
- A bug fix carries its own proof: revert the fix, run the new test filtered, see it go red, restore. Run
  the same single mutation when the reviewer says it cannot tell whether a test is able to fail. Two traps
  make that check lie: the runner tests whatever assembly is loaded, so confirm the recompile finished
  after the mutation before trusting the result; and `git checkout <path>` does nothing on an untracked
  file, so commit new files before mutating them and print the mutated region both times.

### Phase 4: demo, only when asked

A demo is not a default. Build one when the document or the request asks for it. Then it is a small scene
that shows the feature at its best, not a smoke test: someone opens it, presses Play, and understands what
you built. It lives where the project keeps demos (`CLAUDE.md`, or the existing demo folders), covers the
feature's range, and is deterministic on Play. Confirm it runs: save, enter play mode, read the console for
errors, capture the game view (`capture.game_view`, which photographs overlay UI too).

### Phase 5: readability pass

The code works and its tests are green. Before you review it for anything else, run the readability pass
from the `architecture` skill over the actual diff, inside every changed submodule. Re-read that skill
first: in a long run its rules may have been compacted out of your context, and this phase is only as good
as the rules in front of you. Fix what the pass finds (rename reaches tests, serialized fields, assets,
tooltips and docs), keep the user's names and names of unknown origin, touch only what the diff adds, and
keep the record for Phase 7: comments deleted, comments kept with reasons, names changed, methods split,
literals named, anything left unfixed. Recompile and re-run the filtered tests.

### Phase 6: self-review

Walk your own diff, not your memory of it, inside every changed submodule: dead code, leftover logs, a
requirement with no line of code behind it, a bad pattern copied forward. Close those now so the
independent reviewer spends its attention on what you could not see. Fix, then re-run the filtered tests.
No reviewer, no full suite, no build here. **Procedure: `${CLAUDE_SKILL_DIR}/references/hand-off.md`.**

### Phase 7: the feature document

The next agent may pick this up cold. Status, what was built, every decision and assumption, refactors done
and proposed, the readability record, known gaps, existing tests changed, disputed tests, documentation,
branches and PRs. Review and build results are added in Phase 10. **Procedure: `hand-off.md`.**

### Phase 8: documentation

A feature nobody can find is unfinished. Documentation goes in every module the feature changed, in that
module's own convention and index, committed with the feature. A design spec is not documentation.

### Phase 9: commit and open the PRs

Feature branch always, never `main`. In a superproject, submodules commit before the superproject pointer
bump, and submodule PRs open before the superproject PR. Opening them is not the end of the run.
**Procedure: `${CLAUDE_SKILL_DIR}/references/commit-and-pr.md`.**

### Phase 10: review, fix, verify once, close out

Hand each PR to the plugin's `reviewer` agent, one per PR, the PR as the whole target, with the project
path, the PR URL and the feature document, plus one line: code, tests, assembly definitions and docs only,
no scene, prefab or asset opened. Fix what it finds. Then, once, run the full suite and the player build
with the demo scene included and compare both against the Phase 1 baseline. Commit the fixes as a
follow-up, push to the same PRs, complete the PR bodies and the feature document. Never merge.
**Procedure: `hand-off.md`.**

## Delegating

Two delegations, both pre-authorized by the user invoking this skill: the Explore subagent for Phase 0 and
the `reviewer` agent for Phase 10. The reviewer runs on the model you are running on: pass no `model`.
Implementation is never delegated (you need the code you wrote in context to keep going), and neither are
Phase 9 or the Phase 10 commits and PR edits: a cold agent plus the authorship rule is exactly the
combination that puts a forbidden trailer into a PR under the user's name. Subagents never touch the
Editor; you own it for the whole run. Reuse an agent you already spawned with `SendMessage` rather than
starting cold.

## Definition of done

- The design was approved, or came whole from the document; every later ambiguity decided and recorded,
  nothing left waiting on the user.
- Baseline taken before the first change; full suite and player build run once after the review fixes and
  compared against it; no new failures, no new build errors; `total` = baseline + the tests you added.
- Tests exist for everything testable and each can fail; a bug fix's test was seen red with the fix
  reverted.
- No pre-existing test deleted, ignored or weakened; any edited for a spec change is in the hand-off with
  the spec line; any disputed is left red and reported.
- Readability pass run on the actual diff with its record in the hand-off; self-review done.
- Every PR with code reviewed by the `reviewer`, handed the PR and nothing wider; every *fix before merge*
  fixed and pushed; everything left open argued in the PR body.
- Feature document and PR bodies carry the decisions, the review outcome, the test and build results.
- Documentation written in every changed module.
- Committed as the user on feature branches, submodules first; nothing on `main`; nothing merged; no trace
  of Claude as author or co-author.
- The final summary names the PR URLs in merge order, the review outcome per PR, the results against the
  baseline, and what waits on the user. A phase skipped or a box unchecked is said plainly.
