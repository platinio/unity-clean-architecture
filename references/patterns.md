# Game programming patterns for Unity

This is Robert Nystrom's *Game Programming Patterns* catalog, carried over to Unity and C#. Start from the problem you have, not from a pattern you like: find the section whose problem statement matches, and read the whole section before writing code. The "do not use when" and failure-mode notes are the part that saves you time. The samples use plain C# events, `MonoBehaviour` and `ScriptableObject` so they fit any project. If the project already has a reactive library (UniRx, R3), a DI container (Zenject, VContainer, Reflex) or an async library (UniTask), write the same shape in that idiom.

## Contents

- [Command](#command)
- [Flyweight](#flyweight)
- [Observer](#observer)
- [Prototype](#prototype)
- [Singleton](#singleton)
- [State](#state)
- [Double Buffer](#double-buffer)
- [Game Loop](#game-loop)
- [Update Method](#update-method)
- [Bytecode](#bytecode)
- [Subclass Sandbox](#subclass-sandbox)
- [Type Object](#type-object)
- [Component](#component)
- [Event Queue](#event-queue)
- [Service Locator](#service-locator)
- [Data Locality](#data-locality)
- [Dirty Flag](#dirty-flag)
- [Object Pool](#object-pool)
- [Spatial Partition](#spatial-partition)
- [Applying the catalog](#applying-the-catalog)

---

## Command

**Problem.** A request needs a life of its own, separate from the moment it runs. You want to remap it, queue it, undo it, replay it or send it over the wire. Turning the call into an object gives you that: a command is a method call you can hold in your hand.

**Use when.** Input remapping. Undo and redo in tools and turn-based games. AI issuing actions to actors the same way the player does. Replays recorded as a list of commands instead of world snapshots. Networked actions. Any pipeline where actions wait their turn.

**Do not use when.** The call is direct, immediate and carries no state. Command adds a layer of indirection, and a plain method call is cheaper and easier to follow. Reach for the pattern when you need one of the things above, not before.

**Implementation.**

```csharp
public interface ICommand
{
    void Execute();
}

public interface IUndoableCommand : ICommand
{
    void Undo();
}

public sealed class MoveCommand : IUndoableCommand
{
    private readonly IMovable actor;
    private readonly Vector3 delta;

    public MoveCommand(IMovable actor, Vector3 delta)
    {
        this.actor = actor;
        this.delta = delta;
    }

    public void Execute() => actor.Move(delta);
    public void Undo()    => actor.Move(-delta);
}

// Input produces commands; it does not call gameplay directly.
public sealed class CommandQueue
{
    private readonly Queue<ICommand> pending = new();

    public void Enqueue(ICommand command) => pending.Enqueue(command);

    public void ExecutePending()
    {
        while (pending.Count > 0)
            pending.Dequeue().Execute();
    }
}
```

**Design notes.** Keep the data a command needs inside the command. By the time it executes, the surrounding context may have moved on, and a command that reads ambient state at execution time does something different from what was intended. A command that receives its actor at execution time (`Execute(Actor actor)`) can be reused across actors, and that is what lets the AI and the player share one vocabulary of actions. For undo, store the smallest delta that reverses the change. A snapshot of the whole object is simpler to write and far more expensive to keep.

**Failure modes.**
- A new command object every frame is garbage every frame. Pool them, or make commands `readonly struct` and run them through a generic executor.
- Undo that puts the data back but not the side effects. Sound, VFX and statistics have already happened. Either capture a complete reversible delta or state plainly what undo does and does not cover.
- A command holding a reference to something that was destroyed before it ran. Validate the target when you execute, not when you enqueue.

---

## Flyweight

**Problem.** Thousands of instances each carry their own copy of the same data: mesh, stats, description, icon. Memory climbs and the cache suffers for nothing.

**Use when.** Terrain tiles, foliage, projectiles, units of one kind, item definitions. Anything with a clean line between intrinsic state (shared, independent of any one instance) and extrinsic state (what varies per instance).

**Do not use when.** The shared data is tiny or there are few instances. Following a reference to a shared object is itself a potential cache miss, so this is not automatically faster. Profile before calling it an optimisation.

**Implementation.** `ScriptableObject` is the natural flyweight in Unity: one asset, referenced by every instance.

```csharp
[CreateAssetMenu(menuName = "Game/Enemy Definition")]
public sealed class EnemyDefinition : ScriptableObject   // intrinsic, shared, immutable
{
    [SerializeField] private string displayName;
    [SerializeField, Min(1)] private int maxHealth = 100;
    [SerializeField, Min(0f)] private float moveSpeed = 3.5f;
    [SerializeField] private GameObject viewPrefab;

    public string DisplayName => displayName;
    public int MaxHealth => maxHealth;
    public float MoveSpeed => moveSpeed;
    public GameObject ViewPrefab => viewPrefab;
}

public sealed class Enemy : MonoBehaviour
{
    [SerializeField] private EnemyDefinition definition;   // shared
    private int health;                                    // extrinsic, per instance

    private void Awake() => health = definition.MaxHealth;
}
```

**Failure modes.**
- Writing to the shared asset at runtime. In the editor that write lands in the asset file and survives the play session, so the next run starts from a state nobody set on purpose. These bugs look impossible until someone remembers the asset is shared. Shared data is read-only; anything that changes lives on the instance.
- The way to make that stick is in the shape of the class: backing fields are `[SerializeField] private`, and the public surface is read-only properties. Then the compiler refuses the mistake.
- If you genuinely want shared state that changes at runtime, that is a separate design decision with its own consequences. Raise it as one instead of drifting into it.

---

## Observer

**Problem.** One system has to react to something that happens in another, without the producer knowing who is listening, and without a dependency pointing the wrong way. Gameplay must not reference UI.

**Use when.** Wiring together parts of the game that are otherwise unrelated: health to HUD, death to audio, analytics and loot, score to UI, achievements watching gameplay events.

**Do not use when.** You have to understand both sides of the conversation to understand either one. Inside a single feature a direct call reads better and is easier to debug. Observer is for connecting separate lumps of the program, not a replacement for method calls.

**Implementation (plain C#).**

```csharp
public sealed class Health : MonoBehaviour
{
    [SerializeField, Min(1)] private int max = 100;
    private int current;

    public event Action<int> Changed;
    public event Action Died;

    public int Current => current;
    public bool IsDead => current <= 0;

    private void Awake() => current = max;

    public void TakeDamage(int amount)
    {
        if (amount <= 0 || IsDead) return;

        current = Mathf.Max(0, current - amount);
        Changed?.Invoke(current);

        if (IsDead) Died?.Invoke();
    }
}

public sealed class HealthBar : MonoBehaviour
{
    [SerializeField] private Health health;
    [SerializeField] private Image fill;

    private void OnEnable()  => health.Changed += OnHealthChanged;   // symmetric
    private void OnDisable() => health.Changed -= OnHealthChanged;

    private void OnHealthChanged(int value) => fill.fillAmount = value / 100f;
}
```

With a reactive library, publish read-only streams (`IObservable<T>` or `ReadOnlyReactiveProperty<T>`) and keep the writable subject private. Tie each subscription to the owner's lifetime with `AddTo(this)` or a `CompositeDisposable`, so disposal happens without anyone remembering to do it.

**Failure modes.**
- The lapsed subscriber. A subscriber that never unsubscribes stays in the publisher's list. It leaks, and it keeps receiving notifications it should no longer handle. This is the most common observer bug by a wide margin. Subscribe and unsubscribe in matching pairs: `OnEnable` with `OnDisable`, or `Awake` with `OnDestroy`.
- Subscriber destroyed while the publisher lives on. The next notification throws `MissingReferenceException`.
- A lambda with captures cannot be removed by reference, because each evaluation is a new delegate. Hold on to the delegate, or the `IDisposable`.
- The order subscribers are notified in is not defined. Code that depends on it works until it does not.
- Event raises handler, handler raises the same event, and the stack overflows. If that cycle is a real possibility, an Event Queue breaks it.
- Performance is rarely the problem here. Dispatch is a walk down a list plus a virtual call each, and raising an event allocates nothing. Subscribing does allocate, so avoid subscribe/unsubscribe churn in hot loops.

---

## Prototype

**Problem.** You need new objects modelled on an existing one, without a parallel hierarchy of spawner classes mirroring the thing being spawned.

**Use when.** Spawn systems. In Unity a prefab is the prototype and `Instantiate` is the clone, so most of the pattern is already there.

**Do not use when.** You find yourself hand-writing `Clone()` across a class hierarchy. Nystrom is openly sceptical of the classic form: a `clone()` in every subclass costs about as much as the spawner classes it was meant to remove. Prefer generics, factory delegates, or data-driven definitions (see Type Object).

**Implementation.** Keep `Instantiate` in one place, a factory, instead of letting it spread through the codebase. One place to add pooling, parenting and construction later.

```csharp
public interface IEnemyFactory
{
    Enemy Create(EnemyDefinition definition, Vector3 position);
}

public sealed class EnemyFactory : IEnemyFactory
{
    private readonly Transform root;

    public EnemyFactory(Transform root) => this.root = root;

    public Enemy Create(EnemyDefinition definition, Vector3 position)
    {
        var instance = Object.Instantiate(definition.ViewPrefab, position, Quaternion.identity, root);
        var enemy = instance.GetComponent<Enemy>();
        enemy.Construct(definition);
        return enemy;
    }
}
```

**Failure modes.** Prefab variants and nested prefabs are data inheritance. They are useful, and a deep chain of them becomes as hard to reason about as a deep class hierarchy, for the same reasons. Keep the chains shallow.

---

## Singleton

**Discouraged by default.** Nystrom puts Singleton in the book mostly to argue against it, and the argument holds up.

**Why it hurts.** A singleton is global state with a nicer name. Any code can reach it, so you can no longer reason about a function by reading the function. It invites accidental coupling, because any file can reach any subsystem in one line, and the coupling never shows up in a signature. It welds together two unrelated ideas, "there is exactly one of these" and "everyone can get at it", when you usually want only the first. Lazy initialisation takes away control over when the expensive setup runs, and a hitch in the middle of gameplay is the usual price. It blocks substitution in tests and in dev or stub builds. In Unity specifically it gets tangled with scene loading, with initialisation order, and with the domain-reload setting: when domain reload is disabled, static state survives entering play mode and the second run starts with the first run's leftovers.

**What to do instead.** Work down this ladder and stop at the first rung that fits.
1. Delete the manager. A lot of "manager" code is behaviour that belongs on the objects themselves.
2. Pass the object in: a constructor, a `Construct(...)` method, or a serialized reference.
3. Provide it through a base class, so one family of subclasses gets controlled access without making it visible to everyone.
4. Hang it off the one root object you already have, the composition root, instead of adding another global.
5. Service Locator. The least bad global, with the caveats in its own section.

**If a singleton is genuinely unavoidable** (it usually is not), write down why the ladder failed. Have the composition root create the instance explicitly rather than letting it appear lazily, and make its lifetime and its reset explicit so a disabled domain reload cannot surprise you.

---

## State

**Problem.** Behaviour depends on mode, and the boolean flags start combining into states that should not exist (`isJumping && isDead`). When only one flag can be true at a time, that is an enum. When each mode also has its own rules and its own transitions, that is a state machine.

**Use when.** Three or more modes with distinct rules: enemy AI, player locomotion, game flow and screens, match phases, interaction states.

**Do not use when.** There are two modes and the transitions are trivial. An `enum` and a `switch` say the same thing in less code. At the other end, a state machine is not powerful enough for genuinely complex AI; it is not even Turing complete. When the transitions stop fitting, move to a behaviour tree, a goal-oriented planner or utility AI instead of growing a monster machine.

**Implementation.**

```csharp
public interface IState
{
    void Enter();
    void Tick(float deltaTime);
    void Exit();
}

public sealed class StateMachine
{
    private IState current;

    public IState Current => current;

    public void ChangeState(IState next)
    {
        if (ReferenceEquals(current, next)) return;

        current?.Exit();
        current = next;
        current?.Enter();
    }

    public void Tick(float deltaTime) => current?.Tick(deltaTime);
}

public sealed class ChaseState : IState
{
    private readonly EnemyContext context;

    public ChaseState(EnemyContext context) => this.context = context;

    public void Enter() => context.Animator.SetBool(AnimatorHashes.Running, true);

    public void Tick(float deltaTime)
    {
        context.Agent.SetDestination(context.Target.position);

        if (context.DistanceToTarget <= context.Definition.AttackRange)
            context.Machine.ChangeState(context.AttackState);
    }

    public void Exit() => context.Animator.SetBool(AnimatorHashes.Running, false);
}
```

**Variants.**
- Enter and Exit actions put setup and cleanup in one place, so every way into a state behaves the same. Without them the same code gets copied to each transition site and one copy drifts.
- Concurrent state machines. Two independent properties (movement and equipment, say) should be two machines: `n + m` states instead of `n × m`. If the machines have to interact, keep the interaction points few and name them.
- Hierarchical machines. A superstate handles the shared input; substates handle the specifics and hand up whatever they do not cover. This removes the duplicated transitions across an "on ground" or "in air" family.
- Pushdown automaton. A stack of states, for temporary behaviour that has to return to wherever it came from: fire, then resume what you were doing; open a menu, close it, and be back where you were.

**Failure modes.**
- A transition triggered from inside another state's `Enter()` recurses. Guard against it.
- States that know about every other state. Put the transition decisions in the context, or in an explicit transition table, so one state does not have to know the whole graph.
- Per-instance data stored on a state object that is shared or reused. Data belongs in the context.
- Allocating a new state object on every transition. Cache the stateless ones.

---

## Double Buffer

**Problem.** Something reads a set of state while that state is being written, so it sees a half-updated world. Visually that is tearing. In logic it means the result depends on iteration order.

**Use when.** Everything has to resolve at once: cellular automata, simulation ticks, "everyone acts simultaneously" combat, physics-like world stepping where A's update must not see B's brand-new value this tick.

**Do not use when.** Sequential updates are fine. Most gameplay reads current values and nobody notices.

**Implementation.** Read from `current`, write to `next`, swap at the end of the tick. Swap the references rather than copying arrays, and do not allocate new buffers per tick.

```csharp
public sealed class SimulationGrid
{
    private Cell[] current;
    private Cell[] next;

    public SimulationGrid(int size)
    {
        current = new Cell[size];
        next = new Cell[size];
    }

    public void Tick()
    {
        for (int i = 0; i < current.Length; i++)
            next[i] = ComputeNext(current, i);   // read current only, write next only

        (current, next) = (next, current);     // swap
    }
}
```

**Failure modes.**
- Reading `next` during the tick. The whole point was that nobody does.
- Twice the memory. That matters for large buffers on constrained devices.
- Outside code holding a reference into one buffer breaks the moment the buffers swap. Expose accessors, not the raw arrays.
- The swap has to be atomic from the readers' point of view. That only bites once any of this is threaded or jobified, and then it bites hard.

---

## Game Loop

**Problem.** Keep the progression of game time independent of input and of processor speed.

**Unity provides the loop.** You do not write it. What you own is which callback your code lives in, and how that code treats time.

| Callback | Runs | Put here |
|---|---|---|
| `Update` | once per rendered frame, variable step | input, non-physical logic, visuals |
| `FixedUpdate` | fixed step, may run 0..n times per frame | physics, forces, deterministic simulation |
| `LateUpdate` | after every `Update` | camera, follow, IK, anything that must see final positions |

**How to treat time.** Anything continuous in `Update` is scaled by `Time.deltaTime`, and anything in `FixedUpdate` by `Time.fixedDeltaTime`. Movement that changes speed with the frame rate is a defect, not a quirk of the build machine.

Do not read "was pressed this frame" input inside `FixedUpdate`. Because it can run zero or several times per frame, the press can be missed or read twice. Capture input in `Update` and consume it in `FixedUpdate`.

Determinism matters for replays, networking and debugging. Fixed-step simulation with interpolated rendering is the standard answer. Floating-point accumulation differs between machines, which is a known hazard for anything lockstep.

An uncapped frame rate burns battery on mobile. Target frame rate is a product decision that someone should make on purpose.

For pausing, decide per system between `Time.timeScale` and unscaled time. UI animation usually wants unscaled time so the menu still moves while the world is frozen.

---

## Update Method

**Problem.** Many independent objects each need to advance their behaviour one frame at a time, without anything blocking.

**Use when.** Any per-frame simulation. Unity's `Update()` is this pattern. The centralised ticker is the variant for hundreds or thousands of objects: the engine's dispatch to many `MonoBehaviour.Update()` methods has measurable overhead, and one loop over a list is cheaper and gives you control over the order.

**Do not use when.** The logic is event-driven or runs rarely. Polling in `Update` because it was convenient is how frames get slow. Also do not centralise early; a ticker brings a registration lifecycle that has to be maintained.

**Implementation (centralised ticker).**

```csharp
public interface ITickable
{
    void Tick(float deltaTime);
}

public sealed class TickService : MonoBehaviour
{
    private readonly List<ITickable> tickables = new();
    private readonly List<ITickable> pendingAdd = new();
    private readonly List<ITickable> pendingRemove = new();

    public void Register(ITickable tickable)   => pendingAdd.Add(tickable);
    public void Unregister(ITickable tickable) => pendingRemove.Add(tickable);

    private void Update()
    {
        FlushPending();

        float deltaTime = Time.deltaTime;
        for (int i = 0; i < tickables.Count; i++)   // indexed loop: no enumerator allocation
            tickables[i].Tick(deltaTime);
    }

    private void FlushPending()
    {
        if (pendingRemove.Count > 0)
        {
            foreach (var tickable in pendingRemove) tickables.Remove(tickable);
            pendingRemove.Clear();
        }

        if (pendingAdd.Count > 0)
        {
            tickables.AddRange(pendingAdd);
            pendingAdd.Clear();
        }
    }
}
```

**Failure modes.**
- Changing the collection while iterating it. Adding mid-frame lets the new object act in the same frame it appeared, which is usually not what anyone meant. Removing mid-iteration can skip an object. Defer both, as above.
- Order dependence. Objects update one after another: the earlier ones see last frame's state of the later ones, and the later ones see this frame's state of the earlier ones. If that asymmetry is unacceptable, Double Buffer is the fix.
- State across frames. Code that runs one slice at a time has to carry its own state explicitly, which is exactly where the State pattern comes in.
- Empty `Update()` and `FixedUpdate()` methods still cost a dispatch each. Delete them.

---

## Bytecode

**Problem.** Designers need to author behaviour, not just numbers, without a recompile, and that behaviour must not be able to crash or compromise the game.

**Use when.** Large volumes of authored behaviour (spells, abilities, quests), user-generated content that has to be sandboxed, or content updates shipped without a new binary.

**Do not use when.** Almost always. Nystrom's own warning is that these systems grow like vines into ad-hoc languages with no debugger, no tooling and no design. Before considering it, exhaust the alternatives: config assets, Type Object, Subclass Sandbox, state machines, a node-graph tool, or an embedded scripting language that already comes with tooling.

**If it is genuinely needed**, it is a project-level decision, because it needs a VM, an authoring tool and debugging support, and all three have to be maintained. Raise it with the cost stated. It must not arrive as an implementation detail of one feature.

---

## Subclass Sandbox

**Problem.** Many sibling behaviours (abilities, powers, effects) each combine the same handful of primitive operations, and you do not want every one of them coupled to audio, VFX, physics and so on.

**Use when.** A family of variants where the base class offers a small toolkit of `protected` operations and each subclass implements one sandbox method out of them.

**Do not use when.** The variants differ mostly in data; that is Type Object. Or when there are only one or two variants and the base class would be ceremony.

**Implementation.**

```csharp
public abstract class Ability : ScriptableObject
{
    [SerializeField, Min(0f)] private float cooldown = 1f;

    public float Cooldown => cooldown;

    public void Activate(AbilityContext context) => OnActivate(context);   // template method

    protected abstract void OnActivate(AbilityContext context);            // sandbox method

    // toolkit available to subclasses
    protected static void DealDamage(AbilityContext context, IDamageable target, int amount) =>
        target.TakeDamage(amount);

    protected static void SpawnEffect(AbilityContext context, EffectId id, Vector3 position) =>
        context.Effects.Spawn(id, position);
}

public sealed class FireballAbility : Ability
{
    [SerializeField] private int damage = 30;

    protected override void OnActivate(AbilityContext context)
    {
        DealDamage(context, context.Target, damage);
        SpawnEffect(context, EffectId.Explosion, context.Target.Position);
    }
}
```

**Failure modes.**
- The brittle base class. The toolkit collects every dependency any subclass ever needed, until the base is a stew nobody dares touch. When it starts growing, move the operations into objects on the context (`context.Effects`, `context.Audio`) and let the base delegate to them, or switch to Component.
- Subclasses reaching around the toolkit into global state. That throws away the only reason the toolkit existed.
- Deep inheritance. One level of sandboxing is the pattern; two is a hierarchy with the usual problems.

---

## Type Object

**Problem.** A subclass per variant (`Zombie : Enemy`, `FastZombie : Zombie`, and so on) means a code change and a recompile for every new variant. Programmers become data entry and designers wait on them.

**Use when.** Many variants that differ by data: enemy breeds, weapons, items, buildings, upgrades, levels. For iteration speed this is the highest-leverage pattern in the catalog.

**Do not use when.** The variants differ by behaviour rather than data. Type Object cannot express new behaviour, and forcing it leads to definition assets full of flags that a `switch` somewhere interprets. At that point use polymorphism (Subclass Sandbox), or accept a scripted approach with its cost.

**Implementation.** One runtime class, plus one definition asset per variant.

```csharp
[CreateAssetMenu(menuName = "Game/Weapon Definition")]
public sealed class WeaponDefinition : ScriptableObject
{
    [SerializeField] private string id;
    [SerializeField, Min(0)] private int damage = 10;
    [SerializeField, Min(0.01f)] private float fireRate = 0.2f;
    [SerializeField, Min(1)] private int magazineSize = 30;

    public string Id => id;
    public int Damage => damage;
    public float FireRate => fireRate;
    public int MagazineSize => magazineSize;
}

public sealed class Weapon : MonoBehaviour           // one class for every weapon in the game
{
    [SerializeField] private WeaponDefinition definition;
    private int ammo;
    private float nextShotTime;
}
```

**Design notes.** Definitions can inherit: a definition points at a base definition and the values are resolved once at construction, copy-down. That lets you tune a whole family from one place. Keep the chains shallow for the same reason you keep class hierarchies shallow. Keep a registry too, a catalog asset or an addressable index, so a definition can be found by id when a save is loaded.

**Failure modes.** Instances holding a null or stale definition after content changes. Validate on load. And, as with every shared asset, nothing writes to the definition at runtime.

---

## Component

**Problem.** One class collects every domain, input, physics, rendering, audio, AI, until it is a several-thousand-line file where any change touches systems that have nothing to do with it.

**Use when.** Nearly always in Unity. An entity is a `GameObject` plus narrow components. It also gives you composition without an inheritance explosion: a decoration is an entity with a renderer and no physics, and no class had to be written for it.

**Do not use when.** The "component" has no meaning on its own and always travels with its owner. Then it is a private field or a plain class, not another `MonoBehaviour`. Components have a real cost: more objects to create, initialise and wire together.

**Implementation.**

```csharp
[RequireComponent(typeof(CharacterController))]
public sealed class PlayerMovement : MonoBehaviour
{
    [SerializeField] private MovementDefinition definition;
    private CharacterController characterController;

    private void Awake() => characterController = GetComponent<CharacterController>();

    public void Move(Vector2 input, float deltaTime)
    {
        var direction = new Vector3(input.x, 0f, input.y);
        characterController.Move(direction * (definition.Speed * deltaTime));
    }
}
```

**How components talk to each other**, from least to most decoupled:
1. Through shared state on the owner (position, velocity). Simple, and it creates ordering dependencies: whoever reads second sees whatever the first wrote.
2. Direct references, cached in `Awake` or wired through `[SerializeField]`. Fast and explicit; it couples that specific pair and nothing else.
3. Messages or events, through the owner or an event bus. Loosest, and best for incidental communication: a collision happened, play a sound.

The default is (2) inside one entity and (3) across entities. Pick the loosest coupling that still lets someone read the flow without a debugger.

**Failure modes.**
- `GetComponent` at runtime in a hot path. Cache it in `Awake`.
- Two components that reference each other. Introduce a coordinator, or go through events.
- Logic that needs no Unity lifecycle forced into a `MonoBehaviour`. A plain C# class is easier to test and to reuse.

---

## Event Queue

**Problem.** Separate when a message is sent from when it is handled. Observer decouples who; Event Queue also decouples when.

**Use when.** Audio requests that need batching, deduplicating or prioritising. Analytics. Tutorial triggers. Deferred reactions. Breaking a synchronous feedback loop.

**Do not use when.** You only need decoupling in space, not in time, or you need an answer right now. Queues add real complexity: ordering, latency, lifetime and debugging all get harder, and that cost is paid every day.

**Implementation.**

```csharp
public readonly struct GameEvent
{
    public readonly GameEventType Type;
    public readonly int Payload;

    public GameEvent(GameEventType type, int payload = 0)
    {
        Type = type;
        Payload = payload;
    }
}

public sealed class GameEventQueue
{
    private readonly Queue<GameEvent> queue = new();

    public void Enqueue(in GameEvent gameEvent) => queue.Enqueue(gameEvent);

    public void Drain(Action<GameEvent> handler)
    {
        int count = queue.Count;                 // snapshot: events raised during handling wait for next drain
        for (int i = 0; i < count; i++)
            handler(queue.Dequeue());
    }
}
```

For a fixed-rate, allocation-free queue, the classic implementation is a ring buffer with head and tail indices. It never allocates, it is cache friendly, and it has a defined behaviour when full, which the growable queue above does not.

**Failure modes.**
- Stale world state. By the time an event is handled, entities may be gone and positions have changed. Capture the data you need at enqueue time; do not store references to state that will move.
- Feedback loops. A handler that enqueues an event which triggers itself does not blow the stack. The queue hides the cycle and turns it into a queue that never empties or grows without bound. Snapshot the count, as above, and watch for growth.
- Unbounded growth during a pause or a stall. Cap the queue and log the drops. Growing forever is the worse failure.
- Aggregation is a feature, not a hack. Collapsing duplicate requests inside one drain (the same sound twice this frame plays once, loudest wins) is what prevents audible and visible artifacts.

---

## Service Locator

**Problem.** A genuinely global service (audio device, save system, analytics) is needed all over the place, and threading it through five constructor levels makes every signature unreadable.

**Use when.** The service is singular by nature, the dependency is a cross-cutting concern that does not belong in every public API, and passing it by hand has become noise.

**Do not use when.** It is a gameplay dependency. The locator is not a general substitute for injection. It trades transparency for convenience: dependencies disappear from the call site, which makes reading, testing and debugging harder. Nystrom's advice is to use it sparingly, and he means it.

**Implementation. Registration happens only in the composition root.**

```csharp
public static class ServiceLocator
{
    private static readonly Dictionary<Type, object> Services = new();

    public static void Register<T>(T service) where T : class
    {
        if (Services.ContainsKey(typeof(T)))
            throw new InvalidOperationException($"{typeof(T).Name} is already registered");

        Services[typeof(T)] = service;
    }

    public static T Get<T>() where T : class =>
        Services.TryGetValue(typeof(T), out var service)
            ? (T)service
            : throw new InvalidOperationException($"{typeof(T).Name} is not registered");

    public static void Clear() => Services.Clear();
}

public sealed class GameBootstrap : MonoBehaviour        // the composition root
{
    [SerializeField] private AudioService audioService;
    [SerializeField] private SaveService saveService;

    private void Awake()
    {
        ServiceLocator.Clear();                          // survives domain reload being disabled
        ServiceLocator.Register<IAudioService>(audioService);
        ServiceLocator.Register<ISaveService>(saveService);
        DontDestroyOnLoad(gameObject);
    }

    private void OnDestroy() => ServiceLocator.Clear();
}
```

**Useful variants.**
- Null service. Return a harmless do-nothing implementation instead of throwing, so a missing service degrades quietly. It also gives you a clean way to switch features off: no ads in dev builds, silent audio in tests.
- Decorated service. Wrap an implementation to add logging, profiling or assertions without touching a single call site.

**Failure modes.**
- Temporal coupling. Everything depends on the order of registration. Register everything in one place, early, and fail loudly when something is missing rather than returning null.
- Registering concrete classes instead of interfaces. Then nothing can be substituted and the locator is just a global with extra steps.
- Calling `Get<T>()` in per-frame code. Resolve once during initialisation and keep the reference.
- Static state surviving entry into play mode when domain reload is disabled. That is why the explicit `Clear()` is there.

---

## Data Locality

**Problem.** The CPU stalls waiting for RAM. Chasing pointers between scattered objects causes cache misses, and in a hot loop those misses are the cost.

**Use when.** You have profiled, and cache misses are the bottleneck: thousands of entities updated per frame, particle systems, large simulations.

**Do not use when.** You have not profiled. This is an optimisation pattern, and it costs flexibility and readability that you only earn back if the problem was real.

**Techniques.** Store components of one type in contiguous arrays and walk them linearly, instead of following a graph of references. Split hot from cold: keep the per-frame fields in a compact struct and move the rarely-touched data (loot tables, descriptions, editor metadata) behind a reference. In the hot path prefer arrays of value types over collections of small class instances, so the data you need next is already in the cache line.

**In Unity**, the sanctioned route is the DOTS stack (Entities, Jobs, Burst) and `NativeArray`. Adopting it is a project-level architectural decision with a large cost, so it must not arrive as an implementation detail of one feature. Without DOTS, cheap versions still exist and still pay: struct arrays for particle-like data, no per-element allocation, work batched by type.

---

## Dirty Flag

**Problem.** A derived value is expensive to compute and gets recomputed far more often than the primary data actually changes.

**Use when.** Aggregated stats with modifiers, hierarchical transforms, layout, pathfinding results, save serialisation, any cached projection of primary data.

**Do not use when.** The computation is cheap, or the data changes every frame anyway. Then the flag costs more than it saves and adds a place for bugs.

**Implementation.**

```csharp
public sealed class CharacterStats
{
    private readonly List<StatModifier> modifiers = new();
    private int cachedAttack;
    private bool isDirty = true;

    public int Attack
    {
        get
        {
            if (isDirty)
            {
                cachedAttack = Recalculate();
                isDirty = false;
            }

            return cachedAttack;
        }
    }

    public void AddModifier(StatModifier modifier)
    {
        modifiers.Add(modifier);
        isDirty = true;
    }

    public void RemoveModifier(StatModifier modifier)
    {
        if (modifiers.Remove(modifier))
            isDirty = true;
    }

    private int Recalculate() { /* ... */ return 0; }
}
```

**Failure modes.**
- One write path that forgets the flag, and the cache goes stale without a sound. This is the worst kind of bug because nothing fails; the number is just wrong. Every mutation has to pass through code that sets the flag, which means all the mutators live in this one class and the collection is never handed out for outside modification.
- Deferred cost spikes. All the postponed work lands on the frame someone reads the value. If that hitches, recompute at a controlled point instead of lazily.
- The previous derived value has to stay in memory. It is a memory-for-CPU trade, and it only pays when the computation is genuinely expensive.

---

## Object Pool

**Problem.** Frequent runtime creation and destruction causes allocation churn, GC spikes and heap fragmentation.

**Use when.** Bullets, shells, VFX, damage numbers, audio sources, enemies spawned in waves, UI list items.

**Do not use when.** The object is created once per level, or there are a handful of instances. A pool makes lifetime harder to follow, and that is not worth paying for nothing.

**Implementation.** Unity ships `UnityEngine.Pool.ObjectPool<T>`. Use it unless there is a specific reason not to; it already handles the capacity and collection-check details below.

```csharp
public sealed class ProjectilePool : MonoBehaviour
{
    [SerializeField] private Projectile prefab;
    [SerializeField, Min(1)] private int defaultCapacity = 32;
    [SerializeField, Min(1)] private int maxSize = 256;

    private ObjectPool<Projectile> pool;

    private void Awake()
    {
        pool = new ObjectPool<Projectile>(
            createFunc: () => Instantiate(prefab, transform),
            actionOnGet: projectile => projectile.OnRent(),        // full reset lives here
            actionOnRelease: projectile => projectile.OnReturn(),  // unsubscribe, stop coroutines, hide
            actionOnDestroy: projectile => Destroy(projectile.gameObject),
            collectionCheck: true,                                 // catches double-release in dev
            defaultCapacity: defaultCapacity,
            maxSize: maxSize);
    }

    public Projectile Rent(Vector3 position, Quaternion rotation)
    {
        var projectile = pool.Get();
        projectile.transform.SetPositionAndRotation(position, rotation);
        projectile.Launch(onFinished: Return);
        return projectile;
    }

    private void Return(Projectile projectile) => pool.Release(projectile);
}
```

**Failure modes.** Most pool bugs are one of these.
- Incomplete reinitialisation. A pool does not zero memory the way a fresh allocation does. Velocity, health, timers, trails, subscriptions, running coroutines and animation state all survive the previous owner. Reset everything on rent. Do not rely on the previous owner having cleaned up on return.
- Double release: the same instance handed to two owners. Keep collection checks on in development builds so it surfaces immediately.
- Dangling references to an object that was returned and has since been rented by someone else.
- Subscriptions piling up across rents. Unsubscribe on return.
- Behaviour at capacity. Decide what happens when the pool is empty: grow, refuse, or recycle the oldest or lowest-priority instance. Leaving it undecided means random invisible bugs at peak load, which is exactly when you cannot reproduce them.
- Idle memory. Pooled objects take memory while inactive, and everything they reference stays alive too.

---

## Spatial Partition

**Problem.** "Find everything near X" written as a nested loop is O(n²), and it collapses as the entity count grows.

**Use when.** Hundreds or thousands of entities queried by position: area-of-effect queries, perception, flocking, collision broad-phase, chunk streaming.

**Do not use when.** The counts are small. The cost of maintaining the structure exceeds what the query saves, and the complexity buys nothing.

**Options, from simplest to most complex.**
1. Engine built-ins: `Physics.OverlapSphereNonAlloc`, layer masks, triggers, `NavMesh`. Unity's broad-phase already is a spatial partition. Use it before building one.
2. Uniform grid. Simple and cheap, ideal for evenly distributed objects on a bounded map.
3. Quadtree or octree. Adapts to clustering, supports incremental updates.
4. BSP or k-d tree. Static geometry, balanced queries.

**Failure modes.**
- Keeping the structure current. Every moving object has to be removed and reinserted as it crosses cells, like a hash table whose keys change by themselves. For fast-moving objects that maintenance can cost more than the query it was meant to save.
- Extra memory for the bookkeeping.
- Boundary cases: objects that span cells, objects outside the bounds.
- Measure before and after. If you cannot show the improvement, revert it.

---

## Applying the catalog

Name the problem first, then find the section whose problem statement matches it. Read that section through, including "do not use when" and the failure modes, because that is where the pattern says no to you. Before writing anything, state the cost of the pattern in one line. Then implement it in the project's existing idiom: its DI container, its reactive or async library, its naming. If no section fits, write the simple direct solution. A catalog is a set of answers to problems you actually have, not a checklist to complete.
