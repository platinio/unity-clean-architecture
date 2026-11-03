# Unity pitfalls: what goes wrong at run time

Read this when writing or reviewing code that runs inside the Unity player or editor: lifecycle callbacks, per-frame work, events, deferred work, serialized data, scene flow, saves and editor tooling. Each entry names the failure, why Unity makes it happen, and the fix. These are cheap habits, not micro-optimizations.

## Contents

- Lifecycle and initialization order
- The per-frame path and allocation
- Subscriptions and leaks
- Coroutines and async
- Null and destroyed objects
- Serialization and assets
- Scenes and application flow
- Save data
- Editor code

## Lifecycle and initialization order

| Callback | Use it for | Keep out of it |
|---|---|---|
| `Awake` | initialize yourself: cache `GetComponent`, build internal objects | other objects, which may not have run their own `Awake` yet |
| `OnEnable` | subscribe, register with services | heavy setup, because it runs on every re-enable |
| `Start` | connect to other objects, start the logic | assumptions about another object's `Awake` having run first |
| `Update` | input, non-physics logic, visuals | physics, `GetComponent`, `Find`, allocation |
| `FixedUpdate` | rigidbodies, forces, deterministic stepping | "pressed this frame" input, which can be missed or read twice |
| `LateUpdate` | camera follow, IK, corrections after movement | |
| `OnDisable` | unsubscribe, unregister, return to pool | |
| `OnDestroy` | dispose, cancel tokens, release native resources | |
| `OnValidate` | clamp and derive serialized values in the editor | scene lookups or gameplay logic; it runs on load and on every Inspector change |

In one line: initialize yourself in `Awake`, connect to others in `Start`, subscribe in `OnEnable`, unsubscribe in `OnDisable`.

**Script Execution Order is a hidden global.** It fixes an ordering bug today and breaks silently when someone adds a script. Explicit initialization from one composition root is deterministic and visible in code.

**Constructors and field initializers of serialized types run during deserialization**, on loading threads, before the scene exists. Anything touching Unity APIs there is a latent crash. Move it to `Awake` or `OnEnable` on a MonoBehaviour, or `OnEnable` on a ScriptableObject.

**Static state survives entering Play mode** when domain reload is disabled, which is common for iteration speed. A static cache, a static event, a singleton `Instance`: all carry stale state into the next Play. Reset them with `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]`, or better, do not hold the state statically. Note that `Awake` does not rerun for objects that survived.

**`DontDestroyOnLoad` objects accumulate** if each scene creates its own. Create them in exactly one place.

## The per-frame path and allocation

### Know which path you are on

- **Hot**: per-agent, per-frame logic. Behaviour and state-machine ticks, condition checks, blackboard reads, `Update` on many objects. Fifty agents at 60 fps turns a 1 KB allocation into 3 MB/s of garbage. Per-frame cost here is a real finding.
- **Warm**: sensing and perception on a slower cadence, behaviour start/abort/restart paths, spawning.
- **Cold**: editor authoring, inspectors, one-shot setup. Allocation here is fine. Two cold paths still bite: asset postprocessors, which run on every reimport of every matching asset, and editor repaint, which runs per frame while a window is open.

When the project does not name its paths, infer them from the code and say in the finding that you did. Flagging a cold-path micro-cost as if it were hot is the fastest way to lose the reader's trust for the findings that matter.

### The shape of a performance finding

A performance finding is a question backed by arithmetic, not a reflex. Give the current cost, the multiplier that makes it matter, then Option A (cheap mitigation) and Option B (real fix), each with its trade-off. If you cannot name the multiplier, raise it as a question or leave it out. When you do not know, hand the reader the experiment: "if the Profiler shows this method above half a millisecond at the demo's agent count, take option B; below that, leave it." Anything beyond the list below belongs to the Profiler, not to intuition.

### What allocates every frame

```csharp
private void Update()
{
    GetComponent<Rigidbody>().AddForce(force);          // cache in Awake
    GameObject.Find("Player");                           // wire a reference instead
    foreach (var e in enemies.Where(x => x.IsAlive)) { } // LINQ allocates an enumerator and a delegate
    scoreLabel.text = "Score: " + score;                 // a new string every frame
    var buffer = new List<Enemy>();                      // a new list every frame
    Debug.Log($"pos {transform.position}");              // formatting plus a log every frame
}
```

The same work with nothing allocated per frame:

```csharp
private void Awake()
{
    body = GetComponent<Rigidbody>();
}

private void Update()
{
    body.AddForce(force);
    for (int i = 0; i < enemies.Count; i++)
    {
        if (enemies[i].IsAlive) { /* ... */ }
    }
    if (score != lastShownScore)
    {
        scoreLabel.SetText("Score: {0}", score);
        lastShownScore = score;
    }
}
```

- **LINQ** (`Where`, `Select`, `Any`, `ToList`): enumerator, delegate and often a closure. Option A: hoist the delegate to a cached field if the query stays. Option B: a `for` loop over a cached list. The loop is longer but allocation-free; keep LINQ in cold paths where it reads better.
- **Closures capturing locals** in lambdas passed per tick. Cache the delegate and pass state through an argument instead of a capture.
- **String building**: concatenation, `$"..."`, `.ToString()` per frame, usually for HUD text. Option A: build only when the value changed. Option B: a cached `StringBuilder`, or `TMP_Text.SetText` with its numeric overloads.
- **`new List<T>()` or arrays per call**: reuse a cleared member list; for results handed out, take a buffer from the caller.
- **Boxing**: a struct into `object`, an enum as a dictionary key with the default comparer, `params object[]`, interface calls on a struct without generic constraints. Often invisible; check signatures.
- **Physics queries**: use the `NonAlloc` variants (`RaycastNonAlloc`, `OverlapSphereNonAlloc`) with a reused buffer, and always a `LayerMask`. An unmasked query is garbage and wasted broadphase work.
- **Coroutines**: the iterator state machine on every `StartCoroutine`, plus every `new WaitForSeconds(...)`. Cache wait objects in `static readonly` fields; they are stateless and safe to share.
- **`gameObject.tag == "Enemy"`** allocates a string. `CompareTag("Enemy")` does not.
- **`Animator.SetFloat("Speed", ...)` and `material.SetColor("_Color", ...)`** hash the string every call. Convert once with `Animator.StringToHash` and `Shader.PropertyToID` into `static readonly` fields.

### Repeated lookups

- `GetComponent`, `Find` and `FindObjectOfType` in a per-frame path. Option A: cache in `Awake` or `OnEnable`. Option B: a serialized reference or an injected dependency, so the lookup never happens. `FindObjectOfType` is O(scene) and belongs nowhere hot.
- Reading the same dictionary or blackboard key several times in one tick: read it once into a local.
- `transform.position` crosses into native code on every access. Read it once into a local, and use `SetPositionAndRotation` instead of two assignments.

### Churn and fan-out

- `Instantiate` and `Destroy` cycles for projectiles, effects and agents. Option A: Unity's built-in `ObjectPool<T>`. Option B: a simple stack pool. Pooling introduces state-reset bugs, so flag the churn only when the spawn rate is real, and say the reset risk out loud. Either way, creation goes through a factory or a pool, not scattered `Instantiate` calls.
- Many MonoBehaviours with tiny `Update` methods. Each `Update` has a fixed engine-to-managed call cost; hundreds of them cost real milliseconds before their bodies run. Option: one runner ticking a plain C# list. If the project already has a central ticker, new logic ticks under it instead of adding sibling `Update`s. The trade-off is registration discipline.
- Empty `Update` and `FixedUpdate` methods still get called. Delete them.
- Per-tick work that could be event-driven or cadenced. `Update` polling for a change (`if (target != lastTarget)`) costs every frame and misses same-frame transitions. Option A: a dirty flag or change notification, using the project's existing mechanism if it has one. Option B: tick at a coarser cadence with a stagger so agents do not spike on the same frame. The trade-off is a staleness window, often acceptable for AI.

### Things that are not findings

- `foreach` over arrays, `List<T>` and Unity's generic collections does not allocate. It allocates only on non-generic `IEnumerable` or older custom enumerators.
- `Camera.main` is cached by Unity. Flag it only where a serialized reference is cleaner anyway.
- An extracted method on a hot path. The JIT and IL2CPP normally inline it; do not skip the extraction for imagined performance. If a measurement says otherwise, the measurement goes in a comment.
- Line count alone. A long method is a finding when the length hides a second responsibility or a missed early return.

### Also on the frame path

- `Time.deltaTime` for scaled gameplay; `Time.unscaledDeltaTime` for UI and anything that must keep animating while paused.
- Physics settings matter as much as code: the layer collision matrix, `Rigidbody` interpolation, collision detection mode. Wrong settings look like code bugs.
- No per-frame logging. Guard verbose logging with `[Conditional("UNITY_EDITOR")]` or `#if DEVELOPMENT_BUILD` so release builds do not pay for it.

## Subscriptions and leaks

Every `+=` needs a matching `-=`. Three accepted shapes:

```csharp
// 1) Enable/disable, the default
private void OnEnable()  => weapon.Fired += OnFired;
private void OnDisable() => weapon.Fired -= OnFired;

// 2) Awake/destroy, for wiring that lasts the object's whole life
private void Awake()     => service.Changed += OnChanged;
private void OnDestroy() => service.Changed -= OnChanged;

// 3) Reactive libraries: tie the subscription to the object's lifetime
//    (a CompositeDisposable disposed in OnDestroy, or the library's AddTo(this) equivalent)
```

What goes wrong:

- Subscribing in `Awake` but unsubscribing in `OnDisable`: after one disable/enable cycle there is no subscription at all. Keep the pair matched.
- A missing `-=` means callbacks fire on destroyed objects (the classic `MissingReferenceException` from a lambda) and the subscriber is kept alive by the publisher.
- Pooled objects: unsubscribe when returning to the pool, or subscriptions accumulate with every rent.
- A lambda with captures cannot be removed by reference. Keep a delegate field or an `IDisposable`.
- Static events are the worst offender because the publisher lives forever. Avoid them; where unavoidable, unsubscription is mandatory.
- A "dead" listener is not just a leak. It keeps receiving notifications and reacting to them.

## Coroutines and async

Whatever the project uses, the rules are the same.

- Every deferred operation must be cancellable and must stop when its owner dies. With `CancellationToken`, pass it everywhere. With coroutines, keep the handle and `StopCoroutine` it deliberately.
- A coroutine dies silently with its GameObject: code after the `yield` never runs, and `finally` blocks do not run either. Put cleanup in `OnDisable`, not after the last `yield`.
- `async void` loses exceptions. Return an awaitable, or use the explicit fire-and-forget idiom the project's async library provides.
- Cancellation is a normal outcome, not an error to log as one.
- After an `await`, re-check that the Unity objects you are about to touch still exist.
- `Task.Run` for game logic is almost always wrong, because Unity APIs are main-thread only.
- A coroutine or task that outlives its scene is a leak. Tie its lifetime to a scope you own.
- `WaitUntil` and `WaitWhile` take a delegate, so a capturing lambda allocates a closure each time.
- A `while (true)` loop that can skip its `yield` on some path hangs the editor with no way out except killing the process. Yield unconditionally at the top of the loop body.

## Null and destroyed objects

- `UnityEngine.Object` overloads `==`. A destroyed object compares equal to `null` but is not null, so `?.`, `??` and `is null` skip the destroyed check and the object explodes later. Use `if (obj == null)` or `if (!obj)` for anything deriving from `UnityEngine.Object`; `?.` is fine for plain C# objects.
- `Destroy` is deferred to the end of the frame, so the object is still "alive" for the rest of the current one. `DestroyImmediate` is editor-only.
- Anything that outlives a frame (a queued event, a delayed callback, a cached target) re-validates its references before use.
- Do not return null. Return an empty collection, a Null Object, or throw. Every returned null creates a null check in every caller, and the one that gets forgotten takes the game down.
- Do not pass null unless the API explicitly expects it, so that a null argument is unambiguously a bug.
- A gameplay method that can legitimately fail (no target in range, inventory full) returns a result, not an exception: `bool TryX(out T result)`, an enum outcome, or a Null Object. `TryGetComponent(out var x)` and the whole `TryX` family are the accepted use of output arguments.
- Exceptions are for the exceptional. Not for control flow that happens every frame, and not for conditions you can test first.
- An empty `catch`, or a `catch (Exception)` that logs and continues, turns a crash you would have fixed into corruption you will not find. Validate at the boundary and fail loudly.

## Serialization and assets

- `[SerializeField] private` is how a field reaches the Inspector. A public field can be changed by anything, and the scene ends up defining the architecture instead of the code.
- Validate with attributes (`[Min]`, `[Range]`, and whatever validation package the project uses) rather than runtime checks scattered through code.
- Properties are not serialized. `[field: SerializeField]` on an auto-property works, but the generated backing-field name is fragile across renames.
- Renaming or retyping a serialized field without `[FormerlySerializedAs("oldName")]` loses that value in every existing asset on the next import. For a type that already ships in assets, this is the most expensive mistake in the file.
- ScriptableObject instances are shared. Mutate one at runtime and every user sees the change; in the editor it persists to disk. Treat the asset as a read-only definition and copy into a plain runtime state object per instance. Per-execution state stored on the shared definition is this smell at its most expensive.
- Prefer explicit serialized references over runtime lookups: a wired reference fails loudly in the editor, a `Find` fails at runtime in front of a player.
- Magic strings compile fine and fail invisibly: animator parameters, tags, layers, scene names, blackboard keys as inline literals. Use `static readonly` ids, a constants class, or a typed key mechanism if the project has one.
- `transform.Find("Path/To/Child")` breaks on rename and is invisible to refactoring tools. Use a serialized reference or lookup by component.
- String-based dispatch (`SendMessage`, `Invoke("Method")`, `BroadcastMessage`) has no compile-time check, is slow, and is invisible to refactoring.
- `FindObjectOfType` and friends are not a dependency-resolution strategy at runtime. In editor tooling, use `FindObjectsByType` with an explicit sort mode, outside any hot path.
- A `[SerializeField]` drag-reference that crosses a subsystem boundary is a hidden dependency. If the project has a DI container or a service locator, say why this reference does not go through it.
- Unity owns `.meta` files. Hand-writing one risks GUID collisions that silently rewire references, and logic keyed to asset GUIDs or paths as strings breaks on the first move.

## Scenes and application flow

- One bootstrap scene loads first, builds the composition root, then loads the rest. Everything global is created there, once, not by whichever scene happens to run first.
- Additive loading is the default shape beyond a trivial game: a persistent scene holding services, the UI root and the camera rig, with level scenes loaded and unloaded on top. It removes most reasons to reach for `DontDestroyOnLoad`.
- `SceneManager.LoadScene` blocks. Use `LoadSceneAsync` for anything bigger than a menu. With `allowSceneActivation = false`, progress stalls at `0.9`; that is the documented "loaded, waiting for activation" value, not a bug.
- Unloading a scene destroys its objects but not the assets they referenced. Textures, meshes and clips stay in memory until `Resources.UnloadUnusedAssets()`, which belongs at a controlled moment such as a loading screen, never mid-gameplay.
- Anything that survives a scene load (services, static state, pools, subscriptions to global events) needs an explicit reset or re-registration path. Write it at the same time as the thing that survives.
- Scene names as raw strings scattered through code are magic strings. Use build indices, an enum or ScriptableObject scene references, resolved in one place.
- Randomness: the engine RNG is fine for cosmetics. Anything that must be reproducible (replays, seeded runs, tests) owns a seeded `System.Random` behind a service.
- Dev-only tooling (cheats, debug menus, test scenes) is compiled out of release builds, not merely hidden.

## Save data

Saving is a subsystem with its own shape, not a `JsonUtility` call somewhere in a MonoBehaviour.

- One interface (`ISaveService`) fronts serialization, storage and migration. Gameplay asks it to save and knows nothing about the format or the location.
- `Application.persistentDataPath` is the only writable location that exists on every platform, and it is not user-visible on mobile or console. Combine paths with `Path.Combine`.
- Objects opt in and describe their own state through an interface (`ISaveable`) with a stable id and methods to produce and restore state. The service moves data; it does not walk the scene graph.
- Ids are authored and stable, not derived from object names, sibling indices or scene paths. All three change when a designer touches the scene, and the save silently binds to the wrong object.
- Version every save file from day one and write the migration when the schema changes. A save that cannot be migrated is a player's lost progress.
- Save your own DTOs (`SavedVector3`, `SavedInventoryItem`), not engine types. Serializing `Transform`, prefab references or MonoBehaviours couples the file format to your class layout, so a rename breaks every existing save.
- Write atomically: serialize to a temp file, then replace. A crash mid-write must not destroy the previous save.
- Saving may allocate and use LINQ; it is a rare, expected pause. Loading during gameplay is not. Budget it or hide it behind a screen.
- Never trust the file. It can be edited, truncated or written by an older build. Validate on load and fall back to a clean default rather than corrupted state.

## Editor code

Editor tooling is real code with real rules, and it is the code most likely to break a build.

- Editor code lives in an `Editor` folder or an Editor-only `.asmdef` and never ships. A `using UnityEditor;` reachable from runtime code is a build error at best and a stripped-symbol crash at worst. Check the asmdef boundary, not just the file location.
- Dependencies point one way: editor code may reference runtime code, never the reverse.
- An `#if UNITY_EDITOR` block that grows logic the runtime silently lacks in builds is a bug waiting for the first device test. Keep such blocks to editor-only concerns.
- The `OnInspectorGUI` or `OnGUI` part is a thin shell. The analysis and transformation logic is plain C# that could be tested.
- Pick the smallest tool: a `PropertyAttribute` plus `PropertyDrawer` for a field-level widget reusable everywhere, a property drawer for one serializable type, a custom editor only when the whole inspector needs to change. A custom editor per component is a maintenance tax that loses default inspector behaviour.
- Custom editors go through `SerializedObject` and `SerializedProperty`, which give multi-object editing and undo for free. Direct field assignment gives neither, and edits that do not mark the asset dirty are silently lost.
- Allocation or LINQ inside `OnGUI`, UI Toolkit layout callbacks or per-repaint tree walks makes the tool feel bad. Cache per element and invalidate on change, or move the computation off repaint into an event.
- Asset postprocessors and scripted importers run on every teammate's machine on every import. Scope them to the paths the callback hands you, never `AssetDatabase.FindAssets("")` or loading every asset of a type, and batch writes with `AssetDatabase.StartAssetEditing`.
- `SerializedObject.Update` and `ApplyModifiedProperties` sit outside tight loops.
- Bulk editing tools (migrating prefabs after a refactor, renaming serialized fields, populating references) are a throwaway editor script. Write it instead of hand-editing two hundred prefabs.
