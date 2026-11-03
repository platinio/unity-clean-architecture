# GoF Patterns and Design Principles for Game Code

Read this when you are about to introduce a pattern, or when someone has suggested one and you want a quick verdict on whether it earns its place in gameplay code. It covers the three design principles that sit under SOLID and the 22 classic Gang of Four patterns, each with a verdict for Unity.

## Contents

- Design principles: encapsulate what varies, program to an interface, favor composition
- Catalog: creational, structural, behavioral
- Choosing well

## Design principles

### Encapsulate what varies

Find the parts of the system that are going to change and keep them apart from the parts that will not. The point is to limit how far a change spreads. A pricing rule, a movement algorithm, a save format, a platform API: put each behind its own line so that changing one touches one place instead of the whole codebase.

This works at two scales. In a method, pull the volatile calculation out into its own method. In a class, pull the volatile responsibility out into its own class.

### Program to an interface, not an implementation

Depend on what an object can do, not on what it is. In practice: work out what one object needs from another, write those operations down as an interface, make the dependent class use the interface, and only then pick the concrete class that implements it.

What you get is substitution. A stub in tests, a no-op service in a dev build, a second vendor SDK without touching gameplay.

What it costs is indirection. Do not put an interface in front of something that has never varied and has no reason to; wait until the second or third implementation actually shows up.

### Favor composition over inheritance

Inheritance is the quickest way to reuse code and the quickest way to trap yourself. The problems are well known:

- A subclass cannot shrink the base class. It carries everything, including what it does not need.
- An override has to behave like the base method it replaces, or callers break.
- Encapsulation goes. The parent's internals leak to the children, and parents end up knowing about their children.
- Any change to the base ripples through every subclass.
- Once there is more than one axis of variation (cargo type, engine type, control type) the hierarchy multiplies and you get parallel class trees.

Composition says "has-a" rather than "is-a", and it scales across several axes at once: an entity has a movement strategy, has a weapon, has health. This is why Unity's component model exists, and it is why a chain like `Enemy → FlyingEnemy → FastFlyingEnemy` should make you stop and think.

Aggregation is the looser form: A holds a reference to B but does not own B's lifetime.

## Catalog

Each verdict is for Unity gameplay code. **Core** means reach for it routinely. **Situational** means it pays off in the right spot. **Rare** means it is usually over-engineering in a game.

### Creational

| Pattern | What it does | Verdict for Unity |
|---|---|---|
| **Factory Method** | a base class owns creation; subclasses pick the concrete type | **Situational.** Fits spawners and screen creation, but usually collapses into a plain factory class or a delegate |
| **Abstract Factory** | build families of objects that have to match | **Rare.** Worth it for theme, skin or platform families (a whole UI set per platform); not much else |
| **Builder** | assemble a complex object step by step, and get different results from the same steps | **Situational.** Level and dungeon generation, complex entity assembly, test data builders |
| **Prototype** | copy an existing object without knowing its class | **Core, in engine form.** A prefab plus `Instantiate` is Prototype. Hand-written `Clone()` hierarchies rarely pay off |
| **Singleton** | one instance, reachable from anywhere | **Avoid.** Inject the service or pass it in. A static instance hides the dependency and makes the class impossible to test on its own |

In practice most creational needs in a game are met by one factory class that holds prefab or definition references and a pool. Reach for Builder only when construction genuinely has many optional steps.

### Structural

| Pattern | What it does | Verdict for Unity |
|---|---|---|
| **Adapter** | make an incompatible interface usable | **Core.** Every third-party SDK wrapper is an Adapter |
| **Bridge** | split an abstraction from its implementation so both vary on their own | **Situational.** Input source × control scheme, or ability × delivery method. Stops the class explosion |
| **Composite** | treat a tree of objects as one object | **Situational.** UI hierarchies, inventories holding containers, skill trees, stacked damage modifiers |
| **Decorator** | add behaviour by wrapping | **Situational.** Stacking modifiers and buffs; logging or profiling wrappers around a service |
| **Facade** | one simple interface over a complex subsystem | **Core.** The front door to a subsystem, such as `ISaveService` over serialization, storage and migration |
| **Flyweight** | share the unchanging part of state across many objects | **Core.** A `ScriptableObject` definition shared by every instance is Flyweight |
| **Proxy** | a stand-in that controls access to the real object | **Situational.** Lazy or async asset loading, access control, caching |

Facade and Adapter are the two that keep a codebase livable. Facade tames your own complexity; Adapter tames someone else's.

### Behavioral

| Pattern | What it does | Verdict for Unity |
|---|---|---|
| **Chain of Responsibility** | pass a request down a line of handlers until one takes it | **Situational.** Input layers (UI first, then gameplay), damage pipelines, validation chains |
| **Command** | turn a request into an object | **Core.** Undo, replays, input buffering, queued actions |
| **Iterator** | walk a collection without exposing its shape | **Core, built in.** `IEnumerable<T>` and `yield return`. Just do not allocate enumerators on hot paths |
| **Mediator** | objects talk through one coordinator instead of to each other | **Situational.** The honest name for a well-scoped coordinator over several components. Turns into a god object if it keeps growing |
| **Memento** | capture and restore state without exposing internals | **Situational.** Save and load snapshots, undo in tools, checkpoints, rewind |
| **Observer** | tell subscribers when something happens | **Core.** Pair every subscribe with an unsubscribe, and do not rely on the order listeners fire in |
| **State** | change behaviour when internal state changes | **Core.** Character and AI state machines, screen flow |
| **Strategy** | interchangeable algorithms behind one interface | **Core.** Movement, targeting, scoring, difficulty, pathing |
| **Template Method** | the base class fixes the skeleton; subclasses fill in steps | **Situational.** The general form of Subclass Sandbox |
| **Visitor** | keep an algorithm separate from the structure it walks | **Rare.** Sometimes used over mixed trees (skill trees, item effects). Heavy syntax, easy to overuse |

**State vs. Strategy.** Same shape, different intent. A Strategy is chosen from outside and the alternatives do not know about each other. A State switches itself from inside in response to events, and states usually know their possible successors.

**Mediator vs. Observer.** A Mediator puts all the communication in one known place; an Observer spreads it out anonymously. Mediator is easier to debug, Observer is easier to extend.

## Choosing well

A pattern is the answer to a problem you already have. If you cannot say the problem in one sentence, you do not need the pattern yet.

Patterns are not features. "Add a Visitor" is not a task. "Make damage rules extensible without editing five classes" is.

The simplest structure that says what you mean wins. In C#, a delegate often does the job of Strategy or Command, `IEnumerable<T>` is Iterator, and a `record` or `readonly struct` is a Memento.

A pattern on the wrong problem is worse than no pattern. It adds a hop to follow while solving nothing, and it tells the next reader a story about the intent that is not true.

Name a class after a pattern only when it really is that pattern (`WeaponFactory`, `DamageVisitor`). A wrong name costs every future reader time.
