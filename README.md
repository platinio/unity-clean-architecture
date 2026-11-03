# unity-clean-architecture

A Claude Code plugin for Unity C#. Four skills, one reviewer agent, one hook:

| Skill | What it does | When it loads |
|---|---|---|
| `architecture` | The code standard: names, method shape, comments and summaries, the readability pass, SOLID as five questions, game programming patterns picked from the problem, layers and dependency direction, the C# and Unity pitfalls behind leaks and allocations | Writing, refactoring, renaming, reviewing or explaining C# in a Unity project |
| `code-review` | A senior developer's review of a PR, a branch or a folder: a prioritized report of bugs, weak tests, smells, structure, readability and performance, each finding argued with its cost and its fix | "Review PR 14", "what needs fixing here", "is this good" |
| `toolbox` | The Arcane Onyx way of shaping a feature: one-job components, Zenject at scene and character level, a provider interface for what only the game knows, Hermes events when another system must react, designer data in assets and databases; how to detect and install those tools | Designing a feature, deciding where a value lives or how two systems talk |
| `feature` | A feature document in, reviewed pull requests out: baseline, implement, tests that can fail, readability pass, self-review, hand-off, docs, branch, commits, PRs, independent review, fixes pushed | `/unity-clean-architecture:feature <document>` |

The `reviewer` agent is a read-only context the `feature` skill spawns once per PR. The one hook keeps
that agent out of scenes, prefabs and assets: a reviewer judges code.

## Install

```bash
claude plugin marketplace add platinio/unity-clean-architecture
```

```bash
claude plugin install unity-clean-architecture@platinio --scope user
```

`--scope user` makes it available in every project on the machine, CLI and desktop app alike. On Claude
Code 2.1.275 or later the two steps are one:

```bash
/plugin install unity-clean-architecture --marketplace platinio/unity-clean-architecture
```

The `feature` skill drives the Unity Editor through the `unity` CLI (the Unity Editor Pipeline package and
its command line). The three knowledge skills and the review need nothing beyond `git` and `gh`.

Auto-update is off for a non-official marketplace. Update by hand:

```bash
claude plugin update unity-clean-architecture@platinio
```

## Use

**Day to day, in plain words.** "Add a stamina bar that drains on dodge and refills while idle." The
`architecture` and `toolbox` skills load on their own and the first reply is a design: which component
owns the work, where each tunable value lives, which reactions cross a system and become events, the
pattern or "no pattern", with the open decisions as lines. Any C# you paste for a change gets the same
standard applied. "Where should the dodge cooldown live?" is a `toolbox` question.

**A review.** "Review PR 14", or `/unity-clean-architecture:code-review 14`. A branch or a folder works the
same way. The report lands in `<project>/code-reviews/` and a chat summary carries the verdict and the top
three findings. Scenes, prefabs and assets are never opened; they are listed by name.

**A feature, document to reviewed PRs.**

1. Write the feature document where the project keeps specs. When it already carries the design (owning
   component, where each value lives, cross-system reactions, pattern or none), the skill runs straight
   through. When it does not, the first reply is that design and nothing is written until you say go.
2. `/unity-clean-architecture:feature docs/features/12-stamina.md`
3. The run is unattended from there: the Editor is checked, the suite and the player build are baselined,
   the feature is implemented and tested, the readability pass and self-review run over the diff, the
   hand-off is written back into the document, documentation goes into every changed module, a feature
   branch per repository is committed (submodules first) and its PR opened (submodule PRs first), one
   `reviewer` agent reads each PR, the fixes are pushed, the full suite and the build run once more, and
   the PR bodies are completed.
4. You get back the PR URLs in merge order, the review outcome per PR, test and build results against the
   baseline, and what waits on you. You review and merge; the skill never merges.

**Only the readability pass.** `/unity-clean-architecture:architecture` and the files or the diff to look
at. The pass starts from a list of every comment, name, method, literal, type and test the change adds,
plus every guard the touched files repeat, and checks each one.

**What the project should provide.** A `CLAUDE.md` that names the repository topology (submodules and
their paths), where specs and demo scenes live, the test-assembly convention and any commit rules. An
optional `.claude/code-review-profile.md` tells the reviewer which code paths are hot and which house
patterns to cite. Without them the skills infer from the code and say what they inferred.

## What is in it

```
.claude-plugin/plugin.json          the plugin
.claude-plugin/marketplace.json     the marketplace that lists it
skills/architecture/SKILL.md        the code standard and the readability pass
skills/code-review/SKILL.md         the review, plus scripts/review-diff.ps1 (a PR's change without its assets)
skills/toolbox/SKILL.md             the Arcane Onyx way
skills/feature/SKILL.md             the eleven phases, plus references/ for the Unity CLI, commits and PRs, the hand-off
agents/reviewer.md                  the read-only reviewer the feature skill spawns
hooks/                              the asset guard for the reviewer agent, and tests/ for it
references/                         shared by the skills, loaded on demand: patterns, GoF, refactoring,
                                    architecture, C# runtime, Unity pitfalls, SOLID in Unity, conventions,
                                    weak tests, real before/after examples, the Arcane Onyx tools
evals/                              cases for `claude plugin eval`
```

## Try it from a local checkout

```bash
claude plugin validate .
```

```bash
claude --plugin-dir .
```

After an edit, `/reload-plugins` in the session. `/plugin` shows what is loaded and any errors. The hook's
tests run with:

```bash
powershell -ExecutionPolicy Bypass -File tests/guard-reviewer-assets.tests.ps1
```

## Releasing a change

Installed copies are keyed by `version` in `.claude-plugin/plugin.json`, so a change reaches no session
until the version changes. Make the change, bump `version` in the same pull request, merge, then
`claude plugin update unity-clean-architecture@platinio` on each machine and start a new session.

A lesson learned in a project goes into the rule as a general statement; the project's own code goes into
`references/examples.md` as a before/after pair.

## Sources

- The author's own readability and design rules, written during reviews of Unity gameplay code.
- Robert C. Martin, *Clean Code* (via wojteklu's summary) and *Clean Architecture*.
- Robert Nystrom, *Game Programming Patterns*, https://gameprogrammingpatterns.com
- Martin Fowler, *Refactoring*; Alexander Shvets, refactoring.guru.
- Jeffrey Richter, *CLR via C#*.
- The structure of the pattern and architecture references follows Aleksandr Pershin's
  unity-code-architecture skill; the text here is the author's own.

MIT licensed.
