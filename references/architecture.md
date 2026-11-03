# Architecture: Components, Boundaries, Policy

Read this when the question is bigger than one class: which classes belong in which assembly, which way the references should point, where to draw a line between two parts of the game, and how to keep a `MonoBehaviour` out of the way of the rules it hosts. It takes the component principles from Clean Architecture and puts them in terms of Unity assemblies, folders and `MonoBehaviour`s.

## Contents

1. The two values of software
2. Policy, level and the Dependency Rule
3. Component cohesion: what goes in one assembly
4. Component coupling: which way the arrows point
5. Boundaries: where to draw a line, and what it costs
6. The Humble Object
7. Screaming architecture
8. The engine and the frameworks are details
9. The composition root
10. The test boundary
11. Deferring decisions

## 1. The two values of software

Every piece of code is worth two things. It does what was asked today, and it can be changed to do something else tomorrow.

The second one is worth more, and it is the one that gets sold off first, because behaviour is urgent and structure is only important. A game that works but cannot be changed will stop working the moment requirements move. A game that does not work yet but is cheap to change can be made to work.

That is the reason for everything else in this file, and it is also the limit on it. In a game, shipping is a hard requirement and a prototype is a legitimate thing to build. The aim is not to maximise structure. It is to spend structure on purpose, where change is actually coming.

## 2. Policy, level and the Dependency Rule

Policy is a game rule: how damage is computed, when a wave spawns, what a quest needs. Detail is everything that lets a rule talk to the world: the engine, input, UI, the save format, the ad SDK.

Level is distance from input and output. Damage math is high level. `Rigidbody.AddForce` is low level.

The Dependency Rule says source-code dependencies point inward only, toward higher-level policy.

```
Bootstrap / composition root ─┐
UI / Presentation ────────────┤
Integrations (SDK wrappers) ──┤ ──►  Gameplay / Domain  ──►  Core abstractions + Data
Editor ───────────────────────┘
```

A high-level rule never names a low-level detail. When control has to flow outward anyway, because the domain needs a sound played, a file saved or a popup shown, you flip the dependency: the domain declares an interface and the detail implements it. That is the one legal way to cross a boundary going out.

What you get for it: damage math you can unit-test with no scene open, an ad SDK you can swap in one class, a save format you can version without touching gameplay, and a prototype you can rip out without ripping out the rules.

## 3. Component cohesion: what goes in one assembly

Three principles pull against each other here. In Unity a component means an `.asmdef`, or a top-level folder if the project has none.

**Reuse/Release Equivalence (REP).** What you reuse is what you release. Things you would version and ship together belong together. If you could not describe an assembly's contents in one release note, it is not one assembly.

**Common Closure (CCP).** Put classes that change for the same reason at the same time in one place, and keep apart those that change for different reasons. This is the Single Responsibility Principle at component scale, and it is the one that matters most while the game is being built. When a designer changes how weapons work, that change should land in one assembly.

**Common Reuse (CRP).** Do not make users of a component depend on things they do not need. This is the Interface Segregation Principle at component scale, and it tells you what should not sit together. If `Project.Core` holds save, audio, pooling, analytics and math, then everything that only wanted a `Mathf` helper recompiles every time the save system changes.

**The tension.** REP and CCP push toward bigger components; CRP pushes toward smaller ones. There is no right answer, only a position for where the project is now. Early in production, lean on CCP: fewer, feature-shaped assemblies that are easy to work in. Once there is a shared package or a second game, slide toward REP and CRP and split the reusable core out.

The layout is expected to move over the life of the project. Looking at it again once a year is maintenance, not churn.

## 4. Component coupling: which way the arrows point

### Acyclic Dependencies (ADP)

No cycles in the component graph.

A cycle fuses the components into one. They release together, test together, and everyone editing any of them steps on everyone else. In Unity a cycle between `.asmdef`s is a compile error, which is the best reason to set them up: the rule polices itself.

There are two ways to break a cycle. Invert the dependency: the inner component declares an interface and the outer one implements it (`Gameplay` defines `IAudioService`, `Integrations` implements it). Or pull out a new component that both sides depend on.

If you ever find yourself adding a backwards assembly reference to make something compile, the architecture is wrong. Fix the direction, not the `.asmdef`.

### Stable Dependencies (SDP)

Depend in the direction of stability.

Stable does not mean unchanging. It means hard to change, because a lot depends on it. You can measure it:

- Fan-in: types outside the component that depend on types inside it.
- Fan-out: types inside that depend on types outside.
- Instability `I` = Fan-out / (Fan-in + Fan-out). `I = 0` is as stable as it gets; `I = 1` is as unstable as it gets.

`I` has to fall as you follow the arrows. Anything you meant to be easy to change (gameplay features, screens, a prototype mode) has to stay unstable. The moment something stable takes a dependency on it, it stops being easy to change, without one line of its code moving.

### Stable Abstractions (SAP)

A component should be as abstract as it is stable.

Abstractness `A` = (interfaces + abstract classes) / all types in the component. A stable component has to be abstract, or its stability makes the whole architecture rigid: nobody can change it and nobody can extend it. An unstable component should be concrete; that is what makes it cheap to change.

Plot `A` against `I` and there are two places not to be.

The Zone of Pain is stable and concrete (`A≈0, I≈0`): everyone depends on it and nothing in it can be extended. In Unity this is the classic `Project.Shared` or `Utils` assembly full of concrete helpers and static managers that every other assembly references. One exception: something concrete that genuinely never changes, like a math helper untouched for three years, sits there harmlessly.

The Zone of Uselessness is abstract with no dependents (`A≈1, I≈1`): interfaces nobody implements, abstract bases nobody derives from. Speculative Generality with an `.asmdef` around it.

The healthy spots are the two ends. Stable and abstract: your `Core` interfaces, domain contracts, data definitions. Unstable and concrete: feature code, screens, integrations, editor tooling.

**What this looks like in a Unity project.** `Project.Core` and `Project.Data` stay small, mostly interfaces and plain data, and everyone depends on them. `Project.Gameplay` is concrete and depends inward. `Project.UI`, `Project.Integrations` and `Project.Editor` are the least stable and nothing depends on them. `Project.Bootstrap` depends on everything and nothing depends on it. That is correct, and it is why Bootstrap is the one place allowed to know every concrete type.

## 5. Boundaries: where to draw a line, and what it costs

A boundary separates things that change for different reasons at different rates. The candidate lines in a game are gameplay and UI, gameplay and engine or platform, gameplay and persistence, gameplay and vendor SDKs, runtime and editor tooling.

A crossed boundary has three parts: an interface on the inner side, an implementation on the outer side, and a plain data structure travelling between them, with every reference pointing inward. Do not hand an entity across as a mutable reference because it is convenient. Do not pass `UnityEngine` types into code you want to unit-test.

Boundaries cost. A full one is an interface, a data structure, an implementation, wiring in the composition root, and one more hop to follow when debugging. There are cheaper partial forms, from cheapest up:

1. **Discipline only.** A folder and a code review rule. Free, and unenforced.
2. **An assembly definition.** The discipline becomes a compile error. Cheap, and the best value for effort anywhere in Unity.
3. **A facade.** One class is the only door into a subsystem. Cheap, but callers still see the concrete types behind it.
4. **A full boundary.** Interface, data structure, implementation, injection.

Pick the cheapest form that removes the pain you have today, and write down which one you picked and why. A boundary you did not need is expensive; a boundary you needed and skipped is more expensive. Deciding later is usually possible as long as the layer split already exists in the folders.

## 6. The Humble Object

Split a behaviour into the part that is hard to test and the part that is easy, and make the hard part as dumb as it can be. The hard part is "humble": it does no computation, holds no rules, and is not worth a test.

The classic case is View and Presenter, and it maps straight onto Unity.

| | Role |
|---|---|
| **View** (`MonoBehaviour`) | Humble. Copies values that are already prepared into `Text`, `Image`, `Animator`. No formatting, no rules, no branching on game state |
| **Presenter** (plain C#) | Takes domain state and turns it into exactly what the view will show: strings already formatted, booleans already decided, colors already picked |
| **Domain** (plain C#) | The rules. Knows about neither |

If the presenter has decided a number is negative and so should be red, the view model carries `"-1 250"` and `isNegative = true`, and the view just assigns them. Everything interesting is now a plain C# class you can test without a scene.

The same split shows up all over a Unity project:

- A `MonoBehaviour` in general is the humble shell. It collects serialized references and forwards lifecycle calls to a plain C# object that owns the logic.
- An SDK wrapper is a humble adapter with testable policy behind it.
- A save system is humble file I/O and a serializer, with testable migration and state mapping behind them.
- Editor tooling is a humble `OnGUI` or `OnInspectorGUI` with testable asset analysis behind it.

The line between hard to test and easy to test is almost always the right place for an architectural boundary. Testability is not a separate goal you trade against design. It is what a right design looks like from the outside.

## 7. Screaming architecture

The top of the source tree should tell a reader what this game is, not what it was built with. Folders called `Managers`, `Controllers`, `Interfaces`, `Abstracts` or `MonoBehaviours` shout the framework. Folders called `Combat`, `Inventory`, `Quests` or `Economy` shout the game.

This is the same rule as organising gameplay by feature rather than by technical kind, and here is why it matters: a feature is what changes together, so feature folders keep each change in one place, while kind folders scatter every change across the tree.

## 8. The engine and the frameworks are details

The relationship with a framework is one-sided. You commit to it; it commits to nothing. Its author solved their problem, not yours, and every "just derive from our base class" buys them coupling and costs you options.

Use the framework; do not let it into your core. The honest version for Unity is that you are already married to Unity, and pretending otherwise gives you a worse codebase than accepting it does. So make the choice on purpose, item by item.

| Married, and that is fine | Keep at arm's length |
|---|---|
| `MonoBehaviour`, `Transform`, `Rigidbody`, `Vector3`, `Mathf`, the lifecycle | ads, IAP, analytics, attribution and push SDKs |
| `ScriptableObject` as the way data is authored | the DI container: wire from the composition root, do not scatter its attributes through gameplay |
| the scene and prefab model | reactive and async libraries, if the domain can say what it needs without them |
| the C# standard library | save and serialization frameworks, inspector plugins, asset-store gameplay kits |

The test is one question: could this vendor disappear next year, and what would that cost me? For `Transform` the question has no meaning. For an ad SDK it is one class if you kept the wrapper, or three months if you did not.

It follows that game rules live in plain C# classes. Not because Unity is bad, but because a rule that does not need the engine can be tested, reused and ported.

## 9. The composition root

The composition root is the dirtiest, lowest-level, least stable component in the system, and that is its job. It is the one place that knows every concrete type, builds the services and picks implementations (real ads or a stub, real save or in-memory), reads configuration and the build or platform, and wires everything up before getting out of the way.

Nothing depends on it. That is what lets you have a different one per build type: a `DevBootstrap` that stubs the SDKs and adds a debug menu is a plug-in, not a `#if` scattered through gameplay.

## 10. The test boundary

Tests are part of the system and they follow the Dependency Rule. They sit on the outermost ring, depend inward, and nothing depends on them.

Do not couple tests to volatile detail. A suite that drives the game through the UI breaks on every UI change. That is a fragile test problem, and the cause is architectural, not a testing mistake.

The design is what lets you test: plain C# rules, injected fakes, a humble view. Where it helps, add a testing API, a deliberate narrow entry point for tests that bypasses the UI, rather than making production internals public one at a time.

## 11. Deferring decisions

A good architecture keeps options open. The decisions worth deferring are exactly the details: which save format, which ads provider, which UI framework, whether the meta-game is server-authoritative, whether that prototype system survives.

You defer a decision by putting a boundary in front of it, not by refusing to write code. Write the simplest thing that works today behind an interface you own, and keep the option to replace it.

The reverse holds too, and in games it matters more: a decision you have already made and will not revisit does not need a boundary. An abstraction guarding a choice that will never change is Speculative Generality with a good excuse.
