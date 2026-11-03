# Self-review, the feature document, and the review phase

Read this at Phase 6 and again at Phase 10. The three phases are the same thing from different sides:
closing the holes before a human has to find them, and leaving behind the context that would otherwise
die with your session.

## Phase 6: self-review

Review your own diff before you commit it: the actual diff, not your memory of what you wrote, and inside
every changed submodule (`git diff` at the superproject root does not descend). Names, comments and method
shape were already checked item by item in Phase 5; this pass is the part only you can do, whether the
feature does what the document said. For each hunk:

- **Do I need this?** Dead code, leftover debug logs, unused serialized fields, speculative parameters,
  commented-out experiments: delete them.
- **Can I make it better?** Duplication to pull out; a case hardcoded where the next feature would reuse it.
- **Is it correct, or did it merely pass?** Walk the hard parts again: null, empty, zero, a destroyed
  object, domain reload, two calls out of order, the same call twice. A case you never wrote a test for is
  a case you have not checked.
- **Did I touch a test I did not write?** Every modified or removed pre-existing test needs its *old
  assertion → new assertion → spec line* entry for the hand-off. If you cannot write that entry, revert the
  test and fix the code.
- **Did I copy a bad pattern instead of fixing it?** Small: fix it now. Large: write it down for the user.
  Never let it pass silently because it matched its neighbours.
- **Does it satisfy each requirement?** Walk the document's requirements one by one; each gets a line of
  the diff pointed at it.
- **What would a reviewer poke at?** Close those holes now. If you cannot close one, say so in the hand-off
  to the four-part bar rather than waiting to be caught.

Fix what you find and re-run the filtered tests for what you touched. The full suite and the player build
do not run here; they run once, in Phase 10, on the code as it stands after the review.

## Phase 7: the feature document

If a document was given, update it, normally in the folder the project's `CLAUDE.md` names for specs. If
that folder lives inside a submodule, the edit is a submodule change and commits with the rest. If no
document was given, put the same content in the final chat summary.

Append or update a section with everything below. Three entries are *pending* until Phase 10: Review,
Player build, and the final test comparison.

- **Status**: done or partial, and what is left.
- **What was built**: files and types added or changed, with paths.
- **Where the demo is**, when there is one.
- **Decisions and assumptions**: every question asked and its answer, plus every ambiguity you resolved on
  your own after go, and every design trade-off where two principles pulled against each other. This is
  the highest-value part: the context that dies with your session otherwise, and the cheapest place for
  the user to overrule you. Include any project fact `CLAUDE.md` did not state that you had to infer, with
  the line you would suggest adding.
- **Refactors done, and refactors proposed**: the small fixes made on the way, and separately the larger
  problems left alone, each to the four-part bar. Repeat the proposals in the final chat summary.
- **Readability pass**: one line of counts (comments deleted, comments kept with reasons, names changed,
  methods split, literals named), then every name left alone because its origin could not be told, as a
  suggestion, and anything else left unfixed.
- **Review** *(Phase 10)*: per PR, the saved report path, which findings were fixed, and every *should
  fix* or *worth discussing* item left, with the reason.
- **Known gaps and pre-existing test failures**, including the baseline's, so the next person does not
  chase them.
- **Player build** *(Phase 10)*: baseline and final result lines, and any build warning that names a type
  you added.
- **Existing tests changed**: every pre-existing test edited or removed, as *old assertion → new assertion
  → the spec line that justifies it*. "None" is the expected answer; say it explicitly. For a bug fix, the
  test you saw go red with the fix reverted.
- **Disputed tests**: any pre-existing test left red because it contradicts a written source: the
  assertion, the document line, the reviewer's view, and what you would change if the user agrees.
- **Documentation**: which files you created or edited, and where they are linked from.
- **Branches, commits and PRs**: branch names per repository, commit SHAs, PR URLs with merge order.

## Phase 10: review the PRs, fix, verify once

### One reviewer per PR, and the PR is the whole target

Spawn the plugin's `reviewer` agent once per PR, with no `model`, so it runs on the model you are running
on. With several PRs, send the calls in one message so they run side by side. It is a read-only context
that runs the `code-review` skill exactly as the user would by hand and returns a tiered report. You do
not run that skill yourself: you wrote the code, and the value of this pass is that the reader did not.

The prompt carries four things and nothing else:

- the project path (the main checkout);
- the PR URL, one per reviewer;
- the path of the feature document, if there is one, so the tests are measured against it;
- one line: code, tests, assembly definitions and docs only; no scene, prefab or asset is opened.

No summary of the change, no "pay attention to" list, no second repository, no folder path. Each of
those widens or bends the review: a reviewer handed a folder audits the folder, and a reviewer told what
the fix does checks your reasoning instead of the code. Do not describe the work as finished, tested or
clean either; a reviewer told what to think agrees. If a decision needs defending, defend it in the PR
body after the review.

Every PR that carries code, tests or docs gets a reviewer. In a superproject a PR that is only a pointer
bump gets none. If no PR could be opened (no remote, `gh` unavailable), hand the reviewer the branch
instead, stated as a diff of the repository path against its base, and say so in the final summary.

The test lens is the part you cannot do for yourself: you wrote the tests in the same pass as the code.
Treat a test finding like any other. Fix it; do not argue it.

### Working through the reports

- Each comes back as the agent's final message. Save it to
  `<projectPath>/code-reviews/<yyyy-mm-dd>-<repo>-pr-<n>.md`, outside `Assets/`, not committed.
- **Fix before merge**: fix all of them. **Should fix**: fix them, or carry each one you do not into the
  hand-off and the PR body with your reason, to the four-part bar. **Worth discussing**: the user's calls;
  put them in the hand-off and the PR body as written, options included.
- The reviewer has no Unity tools and runs nothing. If it flags something only a run can settle, run it
  yourself, including the one mutation it names for a test it cannot tell is able to fail.
- If the fixes were substantial, push them and send the same reviewer a follow-up with `SendMessage`,
  scoped to the new commits ("the PR has new commits `<sha>..<sha>`: did they close 1.2 and 2.1, and did
  they break anything?"), not a fresh pass over the whole PR.
- **Two re-checks at most.** A reviewer asked again will always find something; past the second round you
  are polishing, not converging. Carry whatever is still open into the hand-off and the PR body, argued.
  An open *fix before merge* after two rounds means the design is fighting you: say so plainly.
- A disputed test is the one permitted addition to the prompt: the test, the assertion, the document line,
  without your conclusion. Its answer goes to the user alongside yours; neither of you touches the test.

### Fix, then verify once

Apply the fixes, iterating with filtered test runs. Then, with the fixes in, run the full suite and the
player build with the demo scene included, the commands in `unity-cli.md`. Compare with the Phase 1
baseline: the same failures as the baseline and `total` = baseline + the tests you added; a succeeded
build with no error the baseline did not have. Anything else is yours, fixed in the code, then the suite
and the build run again. Run both even when the review came back clean: nothing has run the whole suite or
built the player since the baseline.

### Push the fixes and close out

- Commit the fixes as a follow-up commit and push it to the same PR. Never amend or force-push an open PR.
  Same order as Phase 9: submodule first, then the superproject pointer.
- Update each PR body (`gh pr edit <n> --body-file …`): replace the *pending* lines with the final test
  comparison and build result, and add the review outcome.
- Update the feature document's *Review* and *Player build* entries and the final test comparison; if it
  is tracked, before the follow-up commit so it rides along.
- Then the final chat summary: PR URLs with merge order, the review outcome per PR, test and build results
  against the baseline, and anything waiting on the user.

Never merge your own PR. This is where your job ends.
