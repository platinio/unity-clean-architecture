# Refactoring: smells and the techniques that treat them

Read this when code already works but is hard to change, or when a review needs a name for what is wrong. A named smell gives the reader a handle and a body of literature; "this feels messy" gives them only your paragraph. The name classifies the finding. The code still has to show the cost.

## Contents

- Using the catalog
- Bloaters
- Object-Orientation Abusers
- Change Preventers
- Dispensables
- Couplers
- Incomplete Library Class
- Refactoring techniques by group
- Structural patterns to name as the fix
- How to refactor safely
- Unity refactoring hazards
- Smell to refactoring to pattern

## Using the catalog

Two uses. In review, name the smell and the technique that treats it: "Shotgun Surgery, treat with Move Method and Inline Class." While refactoring, pick the named technique and apply it in small steps that each compile. The families below follow Fowler's grouping as refactoring.guru presents it, anchored to what each looks like in Unity.

## Bloaters

Code that has grown too large to work with.

| Smell | What it looks like in Unity | Treatment |
|---|---|---|
| Long Method | a tick that senses, decides and acts in one body; you feel like adding a comment inside it | Extract Method; Replace Temp with Query; Decompose Conditional; Replace Method with Method Object |
| Large Class | the god MonoBehaviour that does input, movement, audio and UI | Extract Class; Extract Subclass; Extract Interface; move UI state to a domain object |
| Primitive Obsession | blackboard keys, tags and animator parameters as raw strings; a `float` and a `bool` that always travel together and want to be a small struct | Replace Data Value with Object; Replace Type Code with Class, Subclasses or State/Strategy; Replace Array with Object |
| Long Parameter List | usually a missing context object: a method threading five fields of an existing context type one by one | Introduce Parameter Object; Preserve Whole Object; Replace Parameter with Method Call |
| Data Clumps | the same trio of serialized fields copied across components | Extract Class into a `[Serializable]` type so the Inspector groups it too; Introduce Parameter Object |

Primitive Obsession is the most common smell in gameplay code: floats scattered across MonoBehaviours instead of one config asset, and string keys instead of typed ids.

## Object-Orientation Abusers

The type system used wrong, or not at all.

| Smell | What it looks like in Unity | Treatment |
|---|---|---|
| Switch Statements | the same `switch` on a type or enum in several places; a `switch (nodeType)` growing a case per node is the system's extensibility leaking away | Replace Conditional with Polymorphism; Replace Type Code with Subclasses, State or Strategy; Replace Parameter with Explicit Methods; Introduce Null Object |
| Temporary Field | a field only meaningful during one phase of execution; in Unity often per-run state living on a shared ScriptableObject instead of per-instance state | Extract Class; Introduce Null Object; Replace Method with Method Object |
| Refused Bequest | a subclass overriding a base method to throw or no-op; the hierarchy is wrong | Replace Inheritance with Delegation; Extract Superclass; often a Decorator fits better |
| Alternative Classes with Different Interfaces | two sensors doing the same job with different method names | Rename Method; Move Method; Extract Superclass; unify behind one interface |

One `switch` inside one factory or one serializer is fine, and often the honest solution. The smell is the repeated switch: the same enum interpreted in three places.

## Change Preventers

One change forces many edits.

| Smell | What it looks like in Unity | Treatment |
|---|---|---|
| Divergent Change | one class edited for unrelated reasons: serialization format, runtime behaviour and editor drawing | Extract Class along each axis; Unity's Runtime/Editor assembly split is this rule made physical |
| Shotgun Surgery | adding one type means touching N registries, switches and menus; count N in the finding, that number is the cost | Move Method and Move Field to concentrate the behaviour; Inline Class |
| Parallel Inheritance Hierarchies | every new `FooNode` needs a matching `FooNodeWidget`; tolerable while shallow, flag it when adding one class mechanically forces the twin | Move Method or Move Field so one hierarchy refers to the other; collapse if possible |

## Dispensables

Things whose absence would improve the code.

| Smell | What it looks like in Unity | Treatment |
|---|---|---|
| Comments | a comment that says what the code does | Extract Method or Extract Variable with an explanatory name; Rename Method; Introduce Assertion. Keep the ones that say why |
| Duplicate Code | the same fragment in two places | Extract Method; Pull Up Method; Form Template Method; Substitute Algorithm; Extract Superclass |
| Lazy Class | a component that only forwards to another | Inline Class; Collapse Hierarchy |
| Data Class | fields plus getters and setters, with the behaviour that uses them living elsewhere | Move Method to bring behaviour to the data; Encapsulate Field; Encapsulate Collection; Remove Setting Method |
| Dead Code | unused members and unreachable branches; unreferenced serialized fields are worse, they keep ghost data alive in every asset | delete it, version control remembers |
| Speculative Generality | interfaces with one implementer, `virtual` with no override, "for later" parameters | Collapse Hierarchy; Inline Class; Remove Parameter |

The third copy: two similar classes are tolerable. When the third copy of a pattern appears, the refactor is extraction, into a base class, a decorator or a shared static, if the copies encode the same decision. Copies that merely look alike but answer different questions should stay separate; say which case this is.

A pure Data Class is legitimate for config assets and DTOs. That is Type Object or Flyweight, not a smell. It becomes a smell when logic that clearly belongs to the data lives somewhere else.

## Couplers

Classes welded together.

| Smell | What it looks like in Unity | Treatment |
|---|---|---|
| Feature Envy | a method reading five fields of another class; a behaviour reaching deep into an agent's internals instead of going through the blackboard or port boundary | Move Method; Extract Method then Move Method |
| Inappropriate Intimacy | two MonoBehaviours holding references both ways and editing each other's state | invert one side into an event; Move Method or Move Field; Extract Class; Hide Delegate |
| Message Chains | `agent.GetComponent<X>().Sub.Value.Thing`; one scene-structure change breaks every chain | Hide Delegate; hand the code the thing it needs |
| Middle Man | a class that only delegates onward | Remove Middle Man; Inline Method |

Hide Delegate can create a Middle Man. Both are trade-offs, not absolutes. Stop when the code reads well.

## Incomplete Library Class

An engine or third-party class lacks what you need and you cannot change it. Introduce Foreign Method adds the one missing method as an extension. Introduce Local Extension wraps the class in one of your own. In Unity this is how SDK and asset-store APIs get handled, and the wrapper doubles as the place where vendor namespaces stop.

## Refactoring techniques by group

**Composing Methods.** Extract Method, Inline Method, Extract Variable, Inline Temp, Replace Temp with Query, Split Temporary Variable, Remove Assignments to Parameters, Replace Method with Method Object, Substitute Algorithm. These are the workhorses. Most gameplay cleanups are Extract Method and Extract Variable applied until each method fits on a screen.

**Moving Features Between Objects.** Move Method, Move Field, Extract Class, Inline Class, Hide Delegate, Remove Middle Man, Introduce Foreign Method, Introduce Local Extension. This group turns a god MonoBehaviour into components: Extract Class along domain lines, then Move Method so behaviour sits next to the data it reads.

**Organizing Data.** Self Encapsulate Field, Replace Data Value with Object, Change Value to Reference, Change Reference to Value, Replace Array with Object, Duplicate Observed Data, Change Unidirectional Association to Bidirectional (and back), Replace Magic Number with Symbolic Constant, Encapsulate Field, Encapsulate Collection, Replace Type Code with Class, Replace Type Code with Subclasses, Replace Type Code with State/Strategy, Replace Subclass with Fields. The ones that pay most in Unity:

- Encapsulate Field: `public float speed;` becomes `[SerializeField] private float speed;` plus a read-only property, so the Inspector keeps its access and other code loses write access.
- Encapsulate Collection: return `IReadOnlyList<T>` and expose `Add` and `Remove` methods that keep the invariants, instead of handing out the `List<T>`.
- Replace Magic Number with Symbolic Constant, or better, move the number into a config asset where a designer can reach it.
- Replace Type Code with Subclasses, State or Strategy: the code-level move toward Type Object or a state machine.
- Duplicate Observed Data: keep the value in a domain object and let the view observe it. This is how domain data leaves a UI class.

**Simplifying Conditional Expressions.** Decompose Conditional, Consolidate Conditional Expression, Consolidate Duplicate Conditional Fragments, Remove Control Flag, Replace Nested Conditional with Guard Clauses, Replace Conditional with Polymorphism, Introduce Null Object, Introduce Assertion.

- Guard clauses return early for the invalid cases and leave the main path unindented.
- Remove Control Flag: the `bool` that breaks a loop or gates behaviour is usually a `break`, a `return` or a state machine in disguise.
- Introduce Null Object: a do-nothing implementation (silent audio, empty analytics, no-op ads) replaces null checks at every call site.

**Simplifying Method Calls.** Rename Method, Add Parameter, Remove Parameter, Separate Query from Modifier, Parameterize Method, Replace Parameter with Explicit Methods, Preserve Whole Object, Replace Parameter with Method Call, Introduce Parameter Object, Remove Setting Method, Hide Method, Replace Constructor with Factory Method, Replace Error Code with Exception, Replace Exception with Test.

- Separate Query from Modifier: a method answers a question or changes state, not both. `GetNextTarget()` that also consumes the target produces bugs nobody can reproduce.
- Replace Exception with Test: if the condition can be checked first, check it. Exceptions are for the genuinely exceptional.
- Rename Method has the highest value per unit of risk of anything here. Do it constantly.

**Dealing with Generalization.** Pull Up Field, Pull Up Method, Pull Up Constructor Body, Push Down Method, Push Down Field, Extract Subclass, Extract Superclass, Extract Interface, Collapse Hierarchy, Form Template Method, Replace Inheritance with Delegation, Replace Delegation with Inheritance.

- Extract Interface is what makes a vendor SDK swappable and a system testable.
- Form Template Method produces Subclass Sandbox.
- Replace Inheritance with Delegation cures Refused Bequest, and answers whenever "is-a" turns out to be "has-a".

## Structural patterns to name as the fix

Suggest a pattern only when the smell it cures is present; a pattern without a smell is Speculative Generality. The seven, with their Unity use:

- **Adapter**: wrap a third-party or Unity API behind the project's own interface. The right answer when code calls `UnityEngine.AI.NavMeshAgent` (or a package's internals) directly from a dozen places: one adapter, one place to change.
- **Facade**: one entry point over a messy subsystem. If callers must invoke three managers in the right order to start something, that ordering is an invariant begging to be a facade method.
- **Composite**: treat one and many uniformly. A behavior tree is a Composite; flag code that breaks the uniformity by special-casing leaf versus composite nodes outside the base class.
- **Decorator**: add behaviour by wrapping, not subclassing. When a subclass adds one orthogonal behaviour (logging, cooldown, guard) to a concrete type, the fix is a decorator, reusable over every type.
- **Bridge**: split abstraction from implementation when both vary, such as sensor logic versus sensing backend (raycast, trigger, navmesh sample), so the matrix of combinations does not become a class explosion.
- **Proxy**: control access: lazy-load a heavy asset, cache an expensive query, stub a remote service. "Cache with invalidation" in a performance finding is often a Proxy by name.
- **Flyweight**: share immutable data among many instances. The definition/state split (shared asset plus per-agent runtime state) is Flyweight; per-run state on a shared asset violates it.

## How to refactor safely

1. Refactoring and behaviour change go in separate commits. A reviewer can check "same behaviour, better shape" or "new behaviour"; checking both at once is guessing.
2. Each step compiles and the game still runs. A step that cannot be small is several steps.
3. Put a safety net around the logic first: tests, or at least a written manual check you can repeat. Logic with no test is logic you are changing blind.
4. Start from the smell, not from a solution. Name it, pick the technique, apply it. "I'll rewrite this with a state machine" is where scope creep begins.
5. Stop when the smell is gone. Refactoring has no finish line of its own.
6. Leave each file a little cleaner than you found it: one rename, one extraction, per visit.
7. Do not refactor code about to be deleted or replaced, and do not refactor third-party code at all.

## Unity refactoring hazards

Refactoring Unity code can break data that lives outside the C# files. The compiler will not tell you.

- Renaming a `MonoBehaviour` or `ScriptableObject` class also means renaming the file, because Unity needs the two to match, and keeping the existing `.meta` file so the GUID survives. A lost `.meta` unbinds every prefab and scene reference. Use the IDE rename, not delete-and-recreate.
- Moving a type between namespaces or assemblies can break serialized references. `[MovedFrom]` from `UnityEngine.Scripting.APIUpdating` keeps them resolvable.
- Renaming a serialized field loses its authored value in every asset unless you add `[FormerlySerializedAs("oldName")]`. Keep the attribute until every asset has been re-saved, then remove it.
- Changing a field's type (`int` to enum, `float` to a struct) drops the old value without a warning. Migrate deliberately and check the assets that use it.
- Splitting one `MonoBehaviour` into several means every prefab and scene object needs the new components added and wired. Plan the asset migration as part of the refactor, and write a throwaway editor script for bulk changes instead of hand-editing prefabs.
- After any structural refactor, open the affected prefabs and scenes and look for "missing script" and fields reset to defaults.

## Smell to refactoring to pattern

| Smell | Refactoring | Often ends at |
|---|---|---|
| Repeated `switch` over an enum | Replace Conditional with Polymorphism; Replace Type Code with Subclasses | Type Object, State, Strategy |
| Boolean mode flags | Remove Control Flag; Replace Type Code with State/Strategy | State |
| God `MonoBehaviour` | Extract Class; Move Method | Component |
| Magic numbers everywhere | Replace Magic Number with Symbolic Constant; Replace Data Value with Object | Flyweight / Type Object (config assets) |
| Null checks everywhere | Introduce Null Object | Null Service |
| UI reaching into gameplay | Duplicate Observed Data; Extract Interface | Observer |
| Vendor SDK calls in gameplay | Introduce Local Extension; Extract Interface | Adapter / Facade, integration layer |
| Direct calls that must be deferred | Replace Method with Method Object | Command, Event Queue |
| Expensive recomputation | Extract Method; Self Encapsulate Field | Dirty Flag |
| `Instantiate` scattered around | Replace Constructor with Factory Method | Factory, Object Pool |
