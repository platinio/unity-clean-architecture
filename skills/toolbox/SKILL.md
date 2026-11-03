---
name: toolbox
description: How gameplay is shaped in an Arcane Onyx Unity project - components that do one thing, Zenject at scene and character level, a provider interface for what only the game knows, Hermes events when another system must react, designer data in assets and databases, and the shape of an existing system copied - plus how to tell whether the project has Zenject, Hermes or the ScriptableObject database and how to install one it lacks. Use when designing a feature or a system, deciding which component owns a job, where a tunable value lives, or how two parts of a Unity project should talk to each other.
---

# The Arcane Onyx way of building gameplay

Six ideas. Every system in these projects is built from them, so a reader who knows one system knows
the others, and a new system looks like it was always there.

1. A **component** does one thing and adds that one piece of functionality to a GameObject.
2. **Zenject** wires things together at two levels: what the scene shares, and what one character owns.
3. What only the game knows comes in through a **provider interface**, never through a reference upward.
4. When something happened that another system must react to, raise a **Hermes event**.
5. Anything a designer tunes is **data in an asset**, never a number in a script or on a scene object.
6. **Copy the shape of an existing system.** Same files, same names, same wiring.

How the code itself must read is the `architecture` skill. Load both.

## The design inventory

Before proposing a design, answer these, so nothing surfaces later by accident:

- Which component will own the work, and does one already exist that should grow instead?
- Which values are tunable, and where does each live (the table under *Data for designers*)?
- Which reactions cross a system boundary and need an event? Which stay inside one character?
- Which tools the design needs, and which of them the project has (`arcane-onyx-tools.md`)?
- Which sets of named things the feature adds, which a designer tunes and expects to grow?

Then propose: the options, one recommended, every open decision as a line.

## 1. Components

A GameObject gets exactly the components for the jobs it has and no others. A character that does not
need a job does not get that component.

- **A component named `Manager` or `Brain` does several jobs** and can be split, one piece per PR, into
  components named for each job.
- **A new capability is a new component, not a new subclass.** Inheritance freezes decisions you have
  not made yet; components stack freely.
- **Keep the rules in a plain class; the component is the thin Unity wrapper.** The plain class is
  testable without a scene; the component injects what it needs, calls it from `Update` or a tick, and
  forwards its C# events outward.
- **A component finds its siblings on its own GameObject** (`GetComponent`, `TryGetComponent` in `Awake`)
  and reaches everything else through injection or events. Never `FindAnyObjectByType` or
  `FindObjectOfType`: in a project with injection it is a shortcut around the design.
- **Components that must run in order** share a base class with `Tick(deltaTime)` and sit in a
  serialized, ordered list on the character, so the designer sets the order in the inspector.
- **Do not store someone else's state.** Ask for it when you need it, through an interface the owner
  implements, instead of caching a value you were handed every frame.
- **Gameplay code never does component lookups at call sites.** A module ships extension methods on
  `GameObject` (or the project's character type) so a call reads `gameObject.ApplyMorale(inspired)`. The
  extension does the null check once; an object without the component degrades to a no-op.

## 2. Zenject, at two levels

Zenject is used for exactly two things: a class **declares what it needs** through `[Inject]` and never
constructs or searches for another system's classes; a system **publishes what it offers** from its
installer, the one place it touches the container.

**Scene level: what everyone shares.** A `ScriptableObjectInstaller` holds the bindings the whole scene
shares: the config asset, the services, the roster. Every binding is an interface.

- `Container.Bind<T>()` for what you own. A duplicate `Bind` fails loudly at startup, which catches an
  accidental double registration.
- `Container.Rebind<T>()` only when overriding is the point. It is last-writer-wins, so whoever configures
  the installer asset decides which implementation the whole game uses.
- With the Static Installer convention (`[StaticInstaller(order)]` plus `[AutoAssetGeneration]`), the
  installer is discovered, ordered and fed into every scene automatically. An override gets a strictly
  higher order than what it overrides; two installers that `Rebind` the same type at the same order have
  an undefined winner. Without the convention, the installer is listed on the `SceneContext`.
- **The installer holds a direct reference to its config asset.** Never find it by type or through
  `Resources`: that behaves differently in a build and silently creates a blank asset when the real one
  is missing. The installer validates its data once as the context is built, so an authoring mistake
  lands in the console as an error instead of a hit window that never closes.

**Character level: what one character owns.** A `MonoInstaller` next to a `GameObjectContext` binds that
character's own pieces: its stance, its runner, its motor, its buffer. Two characters never share a runner
or a motor.

```csharp
[RequireComponent(typeof(CharacterBrain))]
public sealed class CombatCharacterInstaller : MonoInstaller
{
    [SerializeField] private Stance stance;

    public override void InstallBindings()
    {
        ReportAuthoringErrors();
        BindMotor();
        BindStance();
        BindTargeting();
        BindRunner();
    }

    private void BindMotor() => Container.Bind<CharacterMotor>().FromInstance(GetComponent<CharacterMotor>());
    private void BindStance() => Container.Bind<Stance>().FromInstance(stance);
    private void BindRunner() => Container.Bind<ActionRunner>().AsSingle();

    private void BindTargeting()
    {
        bool hasTargeting = TryGetComponent(out IActionTargetPicker pickerOnTheCharacter);
        Container.Bind<IActionTargetPicker>()
            .FromInstance(hasTargeting ? pickerOnTheCharacter : new NullActionTargetPicker());
    }
}
```

- **An optional job is an interface with a do-nothing default**, bound when the component is on the
  character and replaced by the default when it is not. The consumer never null-checks.
- **A character sees what the scene binds; the scene cannot see into a character.** Scene code reaches a
  character's pieces through that character's components.
- **A circular dependency between two bindings is solved with `FromMethod`**, not a redesign:
  `FromInstance` injects the instance the moment something asks for it, and the asker may be the thing
  being built.
- **The rules assembly references no framework** (no Zenject, no Hermes), and a test asserts it. Plain
  classes take their collaborators as constructor parameters; the component or the installer does the
  `[Inject]` work.

## 3. The provider interface: what only the game knows

A reusable system needs something only the game knows: a character's starting value, which actions
exist, what the input bindings are. It must not reference the game. So the system declares a small
interface for exactly what it needs, the game implements it, and the installer binds it. The dependency
now points from the game toward the system.

```csharp
public interface IMoraleProvider
{
    int GetStartingMorale(GameObject character);
}
```

On the installer the slot is `[SerializeReference, SubclassSelector] private IMoraleProvider provider;`,
bound with `Container.Rebind<IMoraleProvider>().FromInstance(provider)`, so swapping the whole game's
source is a dropdown pick on one asset.

**When to add an interface, and when not to.** An interface sits at a boundary another system or the game
must cross: a provider the game implements, a service other systems consume, an optional job with a
do-nothing default. Everywhere else, a plain reference. A hard dependency you will never swap is fine; an
abstraction for a dependency you have no intention of replacing only hurts readability.

## 4. Hermes events: when another system must react

Use a Hermes event when **another system** must react: UI, audio, AI, a different character. A reaction
inside one character between two of its own components is a plain C# event, not Hermes.

- **The event carries the GameObject it is about.** Events are scene-wide; listeners filter
  (`if (args.attacker != gameObject) return;`).
- **Define the event before writing the raise.** Events are defined in the Hermes window and generated
  into typed classes; the class exists only after generation.
- **Inject `ISceneGameEvents`** and raise through its dispatcher with a null-conditional, so a scene with
  no events object degrades quietly:
  `sceneGameEvents?.GameEventDispatcher.OnMoraleChangedGameEvent.Raise(gameObject, morale);`
- **Listen in `Start`, not `OnEnable`:** the dispatcher builds its events in its own `Awake`. Remove the
  listener in `OnDestroy`.
- **Wrap every raise and listen in `#if HERMES_EVENTS_GENERATED`**, so a project whose events are not
  generated yet still compiles.
- **The component forwards the plain class's C# events to Hermes.** The rules assembly never references
  Hermes.

## 5. Data for designers

Where a value lives depends on how much it influences the game:

| | Shared by everyone | Differs per character |
|---|---|---|
| Affects gameplay | Central config asset, referenced directly by the scene installer | Its own asset, referenced by the character (a `Stance`) |
| Only affects that object | | On the component (a text colour, a debug overlay position) |

- **A component holds gameplay data only as a reference to an asset**, never as raw numbers. Values on a
  GameObject are hard to find, drift per instance, and are lost when changed in play mode.
- **A consumer asks for a small interface declared next to it** (`IComboMeterSettings`: two values). The
  config asset implements it and the installer binds it. The consumer never sees the whole config.
- **Store a value in the unit a person tunes:** `deadAheadAngle = 6` degrees, not `DeadAheadSine = 0.1f`.
- **Check constants too.** Hard-coded gameplay numbers in a script are worse than fields on a component.
  A "close enough to zero" threshold is not tuning and stays a constant.
- **A set of named things that a designer tunes and that is expected to grow is a database, from its
  first item.** Kinds of press, tags, modifiers, sounds, skills: `ScriptableItem`s in a
  `ScriptableDatabase<T>`, never loose assets in a folder. The count says nothing: two assets that will
  never be three and that nobody tunes stay plain ScriptableObjects. The database buys the editor
  window, a searchable inspector dropdown and stable IDs with no editor code; moving loose assets into one
  later costs every reference. When the database module is in the project, such a loose set is a
  finding, not a choice.
- **A behaviour a designer chooses** is a small interface with `[SerializeReference, SubclassSelector]`
  implementations: a dropdown pick, and the consumer never learns the new option exists.
- **Variants of an asset** share a parent and override only what differs (SO Variant).

## 6. Copy the shape of an existing system

Before writing a new system, open the closest existing one and match it file for file: the data asset
and its database, the component, the provider interface, the installer, the extension methods, the
event. The payoff is that a reader who knows one system knows them all, and deleting a system is deleting
a folder.

An existing system is a model only where it already follows the six ideas. A shape that predates a tool
the project now has, such as loose assets from before the database module came in, is the thing to
replace, not the thing to copy. Code brought in from another project is new code here and gets the tools
this project has.

## A tool the project does not have

When the design calls for a tool the project lacks, never work around it and never install it silently.
It becomes a line of the design proposal: what the tool would do here, why the plain alternative is
worse, and the install options with a recommendation. The user picks during design; the install happens
after go. A tool found missing only mid-build is installed as a git submodule, logged in the hand-off, and
the build continues.

The guard against over-installing: a reaction inside one character is a C# event, not Hermes; a single
tunable config asset does not need the database module; a set of named things that a designer tunes and
that will grow always does, even while it is small. Say which case the design is in.

How to detect each tool, where it comes from, and the steps after installing it:
`${CLAUDE_PLUGIN_ROOT}/references/arcane-onyx-tools.md`.
