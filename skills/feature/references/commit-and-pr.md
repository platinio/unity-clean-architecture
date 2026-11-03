# Commit and open the pull requests

Read this at Phase 9. Never delegate this phase to a subagent: a cold agent opening a PR under the user's
name, without the run's context, is how a branch ships with a wrong or half-true description.

## Branches

Always a feature branch, never `main` or `master`, in any repository. Name it after the task
(`feature/timeline-scrubber`) and use the same name in every repository the feature touches, so they
pair up. If you find yourself on `main`, branch before the first commit.

Invoking the feature skill is the user asking for the PR: it is the deliverable, so pushing your own
feature branch and opening its PR needs no further permission. The authorization covers exactly that:
pushing the feature branch, opening its PR, and in Phase 10 pushing follow-up commits to it and editing
its body. It never covers pushing to `main`, force-pushing anything, or merging.

## Submodules, when the project has them

The project's `CLAUDE.md` says whether it is a superproject and which paths are submodules
(`git submodule status` at the root lists them). When a change touches one:

1. Create a branch inside that submodule, named after the task. Never commit on a detached HEAD.
2. Commit inside the submodule first.
3. Then commit the superproject's updated submodule pointer. The reverse order leaves the parent
   pointing at a commit that does not exist yet.
4. Record every submodule branch and SHA in the hand-off.

`git status` at the root does not show what changed inside a submodule. Check each one.

## Commits

One coherent change per commit, staged by path, never `git add -A`. Feature code, its tests and its demo
can be one commit; an unrelated cleanup is its own, and a refactor made on the way through goes in its
own commit before the feature commit, so the history reads "fix the shape, then build on it". Design
documents and Editor side-effect edits (ProjectSettings, render settings) stay out of the commit unless
the document is the project's spec that Phase 7 updates.

The commit is the user's. No Claude attribution lines, no co-author trailers, anywhere.

## Pull requests

Use `gh pr create`. In a superproject the parent and every submodule are separate GitHub repositories, so
a feature that touches a submodule needs more than one PR, in this order:

1. Push each submodule branch and open its PR first, in its own repository.
2. Then push the superproject branch and open its PR. It carries the pointer bump, so its body links the
   submodule PRs and says they merge first.
3. Post the PR URLs back to the user and record them in the feature document.

The PR body carries:

- What the feature does, in a couple of sentences. This is all the reviewer is told about the change, so
  describe what it does, not how well it went.
- Test status: what you added and that the filtered runs are green, plus the baseline's pre-existing
  failures stated explicitly so a reviewer does not attribute them to you. The full-suite comparison is
  *pending* until Phase 10.
- Build status: the baseline build's target and result, pre-existing errors stated the same way. The
  final build is *pending* until Phase 10.
- Review: *pending* until Phase 10, which adds the outcome.
- The demo scene path and what to look at, when there is one.
- Anything you flagged in self-review and chose not to change, to the four-part bar.
- Links to dependent PRs with their merge order.

Never state a pending result as done. Never merge your own PR. Opening it is not the end of the run:
Phase 10 follows.
