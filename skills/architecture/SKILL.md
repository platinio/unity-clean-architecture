---
name: architecture
description: Architecture and clean-code standard for Unity C# code - names, method shape, comments and the readability pass; SOLID as five questions to ask of a type; game programming patterns picked from the problem, not from fashion; layers and dependency direction; the C# and Unity pitfalls behind leaks and allocations. Use when writing, refactoring, renaming, reviewing or explaining C# in a Unity project, when choosing a pattern or a place for a value, and whenever a message carries C# that must change, even if nobody says "architecture" or "clean code". Not for game design, balance, art or audio.
---

# Unity C#: code that reads like a book, shaped to change

Code is read far more often than it is written, and it is changed more often than it is finished. The
rules below serve both: a method reads like a paragraph to someone who knows the domain but has never
seen the file, and the shape around it makes tomorrow's change cheap. When two rules pull in different
directions, the one that makes the code read more like plain English wins.

Real before/after pairs from reviews where these rules had to be applied:
`${CLAUDE_PLUGIN_ROOT}/references/examples.md`.

## Read the room first

The repository's existing conventions outrank every default here. One consistent style you dislike is
worth more than two competing styles. Before writing, spend a minute on:

| Question | How to tell |
|---|---|
| Is there a DI container? | `Zenject`, `VContainer`, `Reflex`, installers, `LifetimeScope` |
| Plain events or a reactive library? | `event Action` vs `UniRx` / `R3` / `IObservable` |
| Async style? | coroutines, `Task`, `UniTask` |
| Assembly definitions? | `*.asmdef` files, which means layer boundaries are enforced |
| Tests? | test assemblies, `[Test]` / `[UnityTest]`, which says how safely you can refactor |
| Naming? | private field prefix, enum prefix, class suffixes: match them exactly |

Where the repository has no convention, use the default below and say which default you picked.

## Three limits that come before every rule

- **The user's own names win.** When they chose a name, keep it. A rule is never a reason to rename
  what they decided.
- **Explain simply first.** In conversation, say what code does in plain words before mechanics, edge
  cases or pattern names. If the explanation needs a glossary, the code probably needs better names.
- **Longer code is fine when it reads better.** "Keep it simple" means *reads* simply. More small
  methods and more lines are a fair price for clarity.

## Before writing code

1. **Look for what already exists.** Extending a class beats adding one; duplicating a utility is a defect.
2. **State the responsibility in one sentence without "and".** If you need "and", that is two units.
3. **Pick a pattern from the table below, or say "no pattern".** Both are decisions; silence is not.
4. **Contract first.** Public API or interface, then the implementation.
5. **Smallest public surface.** `private`, `internal`, `readonly`, `sealed` by default.
6. **No speculative infrastructure.** An interface, event or abstract base appears for a second real
   implementation, not a hypothetical one.
7. **Every `+=`, `Instantiate`, pool rent and `CancellationTokenSource` gets its release written in the
   same sitting.** A delegate holds its target alive; a leaked subscription is a bug, not a style issue.

## Names

1. **Name things for what they mean, not how they are implemented.** `HitWindow`, not `Active`;
   `HandleAttackWindows`, not `ProcessCrossings`.
2. **Be precise, not generic.** A word that could mean several things in the domain needs a qualifier.
   `ComboWindow`, not `CancelAttack`. A bare `Data`, `Info`, `Value` or `Direction` needs the words
   that make it precise.
3. **Avoid jargon a newcomer would have to look up.** Pattern names and framework slang ("sink",
   "arm", "hydrate") make sense to the author and nobody else. If you would have to explain the
   word, pick a different one.
4. **Booleans are questions.** `Is`, `Has`, `Was`, `Can`, `Should`, so an `if` reads as a sentence:
   `if (isPlaying && HasCurrentActionEnded())`.
5. **Name families the same way.** Siblings share a shape so knowing one predicts the others:
   `HandleWarp`, `HandleHitWindow`, `HandleComboWindow`. Two names that differ only by a number or a
   synonym are one name.
6. **Long and clear beats short and vague.** No abbreviations, no single letters outside a two-line
   loop. `lastAttackPickedAtNode`, not `lastPicked`; `previousTime` and `currentTime`, not `previous` and `t`.
7. **Name the parts of a calculation.** `frameStart`, `frameEnd`, `timeLeftInWindow`, `shareOfDistance`,
   not `from`, `to`, `span`, `fraction`. A named intermediate beats a clever one-liner.
8. **No encodings.** No type prefixes, no scope prefixes, no leading underscore on private fields:
   `config`, not `_config`; `this.config = config` when a parameter shares the name.
9. **Rename everywhere.** Callers, tests and their messages, serialized fields (`FormerlySerializedAs`),
   UI labels, tooltips and docs. An old word left anywhere confuses the next reader.

## Methods

10. **The entry method tells the story.** `Tick` or `Update` reads as a handful of well-named steps;
    a reader can stop there and know what happens. Details sit below, in the order they are called, so
    the file reads top to bottom.
11. **A method is one unit of work, so it can be named exactly.** If a good name is hard to find, the
    method does too much: split it. A name with "And" in it is a warning.
12. **Do not write the same thing twice.** Two branches that each "check, then start" become one method
    both call. A one-line guard counts: four methods opening with `if (!IsRecording || node == null) return;`
    are one question, `CanRecord(node)`, written four times, and a different operand in the second half
    does not make it a different rule. A trivial question method costs nothing at run time. DRY is
    about one decision written once, not about characters: two methods that look alike but encode
    different rules stay separate.
13. **Hide magic values behind a name.** A literal in a call becomes a named constant, or a method whose
    name says why: `HandleWindowsStartingAtZero(attack, position)`, not `HandleAttackWindows(attack, -1f, 0f, position)`.
    A value a designer tunes lives in an asset, in the unit a person thinks in (`deadAheadAngle = 6`
    degrees, not `DeadAheadSine = 0.1f`).
14. **No boolean parameters that change what a method does.** `EndCurrentAction()` and
    `EndCurrentActionAndGoIdle()`, not `Finish(interrupted, stopDriver)`.
15. **Prefer fewer arguments.** Three is a lot. A method threading five fields of one object wants that
    object, or a small type that groups them.
16. **A question changes nothing; a change says so in its name.** A method either answers or acts,
    never both: `GetNextTarget()` that also consumes the target is a bug factory. `TryGetComponent(out x)`
    and the `TryX` family are the sanctioned exception to "no output arguments".
17. **One owner per piece of state.** State is set and reset in one place: `CloseAllWindows()` instead of
    the same five `= false` lines in two methods.
18. **Boundary conditions live in one place.** Off-by-one, edge handling and the guard that opens a
    family of methods are hard to track; put each in one method instead of scattering `-1`, `<=` and
    the same `if (...) return;` around.
19. **Prefer a small value type to a bare primitive** when the primitive carries a meaning: a `Window`
    with `Start` and `End`, not two floats that must travel together.
20. **Do not return `null` for "nothing found".** An empty collection, a Null Object or `bool TryX(out T)`
    means no caller has to remember a check. Do not pass `null` into your own APIs either; then a null
    argument is unambiguously a bug. For `UnityEngine.Object` the check is `== null`: `?.`, `??` and
    `is null` skip the destroyed-object test.

## Comments and summaries

21. **A comment or summary earns its place when it is short and says what the name cannot.** What a
    public type or member is for and how it is meant to be used; a why forced by an outside limit (a
    hardware constraint, an engine quirk, a third-party package that behaves oddly); a consequence the
    reader must know ("this takes 30 s, do not run in CI"). Everything else is a name that failed: put
    the words into the name and delete the comment.
22. **Summaries go on what other code calls.** A public type, or a public member another system uses,
    gets a `/// <summary>` of one to three lines. Private members, fields and parameters get none: a
    comment saying what a field *holds* is the name's job. A summary that restates the type name in
    other words is the same failure as a comment above a method.
23. **Before keeping a comment, ask three questions in order and act on the first yes.** *Can a name say
    it?* Rename. *Is it a guarantee* ("always sorted", "never null")? Enforce it where the value is made,
    or pin it with a test; a guarantee that is only stated is the first thing to become untrue. *Is it
    about anything other than the code it sits beside?* It goes. What is left takes the deletion test:
    cover the name and the public members, read the comment, and if it could have been written from
    those, delete it. Adding information is not the test; a comment is code nobody compiles and no
    test checks.
24. **A comment speaks only about the code beside it.** Never about another file, a test, a design
    document or a change not made yet. Nothing checks those claims, so they rot first. If the claim
    matters, make it a test; if it is a plan, it belongs in the hand-off.
25. **One why, written once; docs follow the code.** A reason that applies to several places is a
    convention and lives in the module's README, not in every file. Commented-out code is deleted; git
    remembers. When a name changes, the README, tooltips and summaries change in the same edit.

## SOLID: five questions to ask of a type

The rules above make a line read well. These five decide whether the line should be there at all. A line
can pass every naming rule and still be wrong:

```csharp
bool isOnTheFloor = stateMachine.Current is KnockedDownState;
```

It reads as a sentence, and it is the mistake O describes. A good name on a type test hides the test.

- **S, one reason to change.** A type does one job. *In code:* it cannot be described without "and"; its
  name ends in `Manager` or `Brain`; unrelated changes keep landing in it. *Do:* split it by job.
- **O, a new case is a new class, not an edit to old code.** *In code:* a test of which class an object
  is (`is`, `as`, `GetType()`); a `switch` on a type or an enum that appears in more than one place; any
  list of cases that grows when a sibling is added. *Do:* ask the object. Put the question on the
  interface and let each implementation answer it.
- **L, any implementation can stand in for its interface.** *In code:* the caller checks the subtype
  before acting; an override that throws, does nothing, or ignores what the base promised. *Do:* as for
  O when the caller is checking; change the hierarchy when an override refuses.
- **I, a caller depends only on what it uses.** *In code:* an implementation with empty or throwing
  members; a consumer handed a whole object to read two values. *Do:* a small interface declared next
  to the consumer, holding only what it asks for.
- **D, depend on an interface the needing code owns, and let the detail implement it.** *In code:*
  `new` on a service inside logic; a search for an object (`FindObjectOfType`, a static `Instance`);
  rules code that names a framework or a concrete class it does not need. *Do:* declare what is needed
  and have it handed in.

Two limits, so these are not applied where they cost more than they save:

- **They are questions for code that has, or is about to have, a second case.** One implementation and
  no second in sight needs no interface. Depending on `Transform` or `Mathf` is depending on the engine,
  and that is fine; invert what is actually substituted: services, data sources, strategies.
- **Asking what an object can do is not a type test.** `TryGetComponent(out IActionTargetPicker picker)`
  asks whether an ability is present; `current is KnockedDownState` asks which class it is. The first
  survives a new class; the second must be edited for each one.

Unity examples for each: `${CLAUDE_PLUGIN_ROOT}/references/solid-in-unity.md`.

## Which rule wins

Conflicts resolve top-down:

1. **It works and it reads.** Clarity beats theoretical purity.
2. **KISS and YAGNI.** The simplest thing that solves today's problem.
3. **The three foundations.** Encapsulate what varies; program to an interface; favor composition over
   inheritance.
4. **SOLID**, as a cure for a concrete pain, not as decoration.
5. **A pattern**, as a proven solution to a concrete problem.
6. **Micro-optimization**, after profiling, except the free wins in `unity-pitfalls.md`.

Architecture is about change: code has a value today and a value tomorrow, and the second is always the
one traded away first because behaviour is urgent and structure is merely important. Decoupling buys
structure at the cost of indirection, so buy it where change is expected, not everywhere. **Rule of
three:** an abstraction earns its place with two real usages and a plausible third. **Cost statement:**
before introducing a pattern, say in one line what pain it removes and what it costs (a layer, an
indirection, an init order, harder debugging); if the cost exceeds the pain, skip it.

## Problem → pattern

| Problem | Pattern | Note |
|---|---|---|
| Behaviour differs by mode; booleans are multiplying | **State**; nested → hierarchical; return-to-previous → pushdown | three behavioural booleans is the signal |
| Two independent properties multiply states (armed × grounded) | **Concurrent state machines** | n + m states instead of n × m |
| Something must notify N unknown listeners | **Observer** | the repo's reactive library if it has one, else `event Action` |
| A request must be deferred, queued, undone, replayed or sent over the wire | **Command** | a method call turned into an object |
| Sender and receiver decoupled *in time* | **Event Queue** | audio, analytics, breaking feedback loops |
| Frequent runtime create and destroy | **Object Pool** | bullets, VFX, damage numbers |
| Behaviour assembled from independent parts | **Component** | Unity's native model: compose, do not inherit |
| Many objects each advance one frame at a time | **Update Method** | hundreds of objects: one ticker instead of N `Update()` |
| A global service needed in many places | **Service Locator**, registered from a composition root | injection > locator > singleton |
| Many objects share identical immutable data | **Flyweight** → shared config asset | intrinsic vs extrinsic state |
| One class, many variants differing by data | **Type Object** → data assets | beats a subclass per enemy breed |
| Objects created from a template | **Prototype** → prefab + factory | prefer factories over `Clone()` hierarchies |
| A family of behaviours built from one toolkit | **Subclass Sandbox** | abilities, effects, powers |
| Expensive derived value recomputed too often | **Dirty Flag** | recompute on read, not per frame |
| State must not tear mid-update | **Double Buffer** | simulations, simultaneous resolution |
| "Find things near X" is O(n²) | **Spatial Partition** | only after profiling |
| Cache misses dominate a hot loop | **Data Locality** | last resort; profile first |
| Designers must author behaviour, not just numbers | **Bytecode / scripting** | very high cost; exhaust simpler options first |

Read `${CLAUDE_PLUGIN_ROOT}/references/patterns.md` before implementing one: it carries the Unity shape,
when not to use it, and the failure modes. The GoF catalog with a Core / Situational / Rare verdict for
game code is `${CLAUDE_PLUGIN_ROOT}/references/gof-patterns.md`.

## Layers and dependency direction

Whatever the folder names, keep these roles apart and let dependencies flow one way:

```
Bootstrap / composition root  →  entry points, wiring
UI / presentation             →  views, presenters, screens
Gameplay / domain             →  rules, entities, systems
Core / infrastructure         →  services, pooling, save, event bus
Data / configs                →  config assets, plain data, no logic
Integrations                  →  third-party SDK wrappers
Editor                        →  editor-only tooling
```

`Bootstrap → UI → Gameplay → Core / Data`. `Core` never knows `Gameplay`; `Gameplay` never knows `UI`;
UI subscribes to gameplay, never the other way. When control must flow outward (the domain needs a
sound played or a file saved), the inner layer declares the interface and the outer layer implements it.
That is the only legal way to cross a boundary outward.

Where assembly definitions exist, each layer gets one, so a layer violation is a compile error. Group by
reason to change, not by technical kind; never add a backwards reference to break a cycle, invert the
dependency instead; and keep the stable assemblies small and abstract. A big concrete `Utils` or `Shared`
assembly that everything references is the classic failure. Third-party SDKs (ads, IAP, analytics) are
used through an interface you own, implemented in the integration layer, so gameplay never has a vendor
`using`. Component principles, boundaries and the Humble Object in detail:
`${CLAUDE_PLUGIN_ROOT}/references/architecture.md`.

## Composition

In preference order: **constructor injection** for plain C# classes; a **serialized reference or an
explicit `Construct(...)`** for a `MonoBehaviour`; the project's **DI container** in its own idiom when
it has one; a **Service Locator** only for a genuinely global service and only registered from the
composition root; a **singleton `MonoBehaviour`** is a no by default, and when it looks unavoidable the
Singleton section of `patterns.md` says what to try first. Never resolve a dependency with
`FindObjectOfType` or `FindAnyObjectByType`.

**Keep the `MonoBehaviour` humble.** The component holds serialized references, forwards lifecycle calls
and moves already-computed values into the scene; the rules live in a plain C# class beside it, testable
without a scene. A view assigns strings and flags a presenter decided; it does not format, branch on
game state or compute. In an Arcane Onyx project the `toolbox` skill says how this is done with Zenject,
provider interfaces and Hermes events.

## Refactoring and bug fixing

1. Write down what the code does today.
2. **Name the smell and the technique that treats it** (Long Method, Feature Envy, Shotgun Surgery,
   Primitive Obsession; `${CLAUDE_PLUGIN_ROOT}/references/refactoring.md`). Diagnosis before treatment;
   never start from "I'll rewrite this with a state machine".
3. Behaviour-preserving steps, each of which compiles on its own. Never mix a refactor with a behaviour
   change; they are separate commits.
4. Check the Unity hazards before a structural move: renaming a type or its file and `.meta`, moving a
   type between assemblies, renaming a serialized field, splitting a `MonoBehaviour` that prefabs and
   scenes reference.
5. **Root cause before patch.** When a bug is a symptom of a shape problem, fix it narrowly and raise the
   shape problem separately. When a tool needs a workaround, fix the tool.
6. **Leave the lines you touch cleaner than you found them, and only those.** Beyond the change at hand a
   cleanup is reported, not done.

## Red flags to call out on sight

Use the canonical name so the finding has a handle and a literature.

- Floats, ints and strings standing in for concepts → **Primitive Obsession** → typed values, config assets.
- The same group of parameters travelling together → **Data Clumps** → a small type.
- A `switch` or `if` chain over a type or enum in more than one place → **Switch Statements** → polymorphism, Type Object, State.
- One class edited for many unrelated reasons → **Divergent Change**; one change forcing edits in many files → **Shotgun Surgery**.
- A method more interested in another object's data than its own → **Feature Envy** → Move Method.
- `a.B.C.D.Method()` → **Message Chains**; a class that only forwards → **Middle Man**.
- An abstraction with exactly one implementation, added "for later" → **Speculative Generality** → delete it.
- A subclass that overrides members into no-ops → **Refused Bequest** → composition.
- Mutable `static` state → a hidden global dependency, and it survives domain reload.
- Public fields, setters with no reason, a mutable collection returned from a getter → leaking encapsulation.
- Subscribe without unsubscribe → the lapsed listener leak.
- Empty `catch`, a `catch` that logs and continues, or `throw ex;` → a hidden failure or an erased stack.
- A `MonoBehaviour` view that formats, computes or branches on game state → not humble.
- A capturing lambda, LINQ query, string concatenation or `new WaitForSeconds` on the per-frame path →
  an allocation per frame; a struct through `object`, an interface or `HasFlag` in a hot loop → boxing.
- `using UnityEditor;` reachable from runtime code, or editor code outside an Editor assembly.
- Config data mutated at run time on a shared asset → shared-state corruption.

Lifecycle, null, serialization, per-frame cost and the shape of a performance finding:
`${CLAUDE_PLUGIN_ROOT}/references/unity-pitfalls.md`. Allocations, boxing, events and object lifetime:
`${CLAUDE_PLUGIN_ROOT}/references/csharp-runtime.md`.

## The readability pass: running the rules over a change

**The pass runs before the change is committed or handed over, every time**, not when the change looks
big enough to deserve it. Reading your own change and waiting to notice a problem does not work: every
comment and every name looked right when you wrote it. So the pass starts from a list, not from a
read-through: list every item of each kind below and check every item. An item is done when it is fixed,
or when you can name the rule it satisfies.

**Write the list out.** A list held in your head is the read-through this pass replaces, and nothing
afterwards can tell the two apart. The output is one line per item with its verdict: deleted, renamed,
split, or the rule it satisfies.

Start with the count, which needs no judgment: the comment lines the change adds against the lines it
adds in total.

```bash
git diff -U0 | grep -cE '^\+\s*(///|//|#)'    # comment lines added
git diff -U0 | grep -c '^+[^+]'               # lines added
```

Say both numbers. Then count the guards over the files the change touches, not over the diff: a line
repeated across eight methods is rarely a changed line.

```bash
grep -hE '^\s*if \(.*\) (return|continue|break)' <touched files> | sed -E 's/^\s+//' | sort | uniq -c | sort -rn | head
```

Every line with a count above one goes on the list under rule 12, with its siblings that differ by one
operand.

| List every... | Check it against |
|---|---|
| Comment and summary the change adds | Rules 21 to 25. Kept only when it is short, needed, and says what the name cannot |
| Type, member, field and parameter it adds or renames | Rules 1 to 9 |
| Method it adds or changes | Rules 10 to 20 |
| Condition the guard count shows more than once | Rule 12, and 18 when it is an edge case. Fixed when the change already rewrites the methods it opens; reported otherwise |
| Literal it adds | Rule 13 |
| Type it adds | SOLID S, I and D |
| Test of which class an object is (`is`, `as`, `GetType`), and `switch` on a type or an enum | SOLID O and L: could the object answer the question itself? |
| Test it adds | One idea per test, named for the behaviour it proves; fast, independent, repeatable; able to fail for a real reason |

The limits at the top still hold. A name the user chose is not on the list. A name whose origin you
cannot tell, such as one copied from a specification, is not renamed: it is reported as a suggestion.
Only what the change adds or touches is fixed; anything older is reported. A method the change rewrites is
touched whole, unchanged lines included.

A reviewer runs the same pass without editing and reports what the list turns up as one finding that
names every item, not as scattered remarks.

## Output formats

**New code or a feature:**

```
Problem:  one sentence
Approach: the pattern(s) and why, or "no pattern, KISS"
Files:    paths and the role of each

<code>

Trade-offs: what was simplified and why
Open questions: if any
```

**An architecture choice:** two or three options at most, each with essence, upside, downside and cost,
then one explicit recommendation. Never a survey without a recommendation.

## References

Load on demand, never all up front. All under `${CLAUDE_PLUGIN_ROOT}/references/`.

| File | Read it when |
|---|---|
| `examples.md` | you want to see a rule applied: real renames, kept and dropped comments, the type-test fix |
| `patterns.md` | implementing any game programming pattern; required before writing one |
| `gof-patterns.md` | choosing among the classic GoF patterns; the three foundations under SOLID |
| `solid-in-unity.md` | explaining why something violates one of the five questions, with Unity code |
| `refactoring.md` | reviewing or refactoring: smell catalog, techniques, safe process, Unity hazards |
| `architecture.md` | cutting assemblies, drawing a boundary, Humble Object, "is this a detail?" |
| `csharp-runtime.md` | allocations, boxing, GC, struct vs class, events and lifetime, `const` vs `static readonly` |
| `unity-pitfalls.md` | lifecycle, per-frame cost, leaks, null and destroyed objects, serialization, save data, editor code |
| `conventions.md` | naming, file layout, namespaces, assembly definitions, tests, when the repository has no convention |

## Sources

- The author's own readability rules, written during reviews of Unity gameplay code.
- Robert C. Martin, *Clean Code* (via wojteklu's summary) and *Clean Architecture*.
- Robert Nystrom, *Game Programming Patterns*, https://gameprogrammingpatterns.com
- Martin Fowler, *Refactoring*; Alexander Shvets, refactoring.guru.
- Jeffrey Richter, *CLR via C#*.
- The structure of the pattern and architecture references follows Aleksandr Pershin's
  unity-code-architecture skill; the text here is the author's own.
