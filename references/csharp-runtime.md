# C# and the CLR: Semantics That Shape Game Code

Read this when the question is "why does this allocate", "should this be a struct", "why is this object still alive", or "why does this behave differently in a build". It covers the parts of the runtime that change a decision in a Unity project and leaves out the rest.

**Unity's runtime, briefly.** Unity does not run on .NET's server or workstation GC. Mono's collector is conservative and non-generational. Incremental mode spreads a collection across frames but does not make it free, and there is no cheap gen-0 to soak up short-lived garbage. IL2CPP compiles ahead of time, so anything that needs code generated at runtime (`Reflection.Emit`, `dynamic`, some generic virtual dispatch over value types) either fails or falls back to something slow. The practical upshot: treat every allocation as real, and treat reflection as an editor and build-time tool, not a runtime mechanism.

## Contents

1. Value types vs reference types
2. Boxing
3. Where per-frame garbage comes from
4. Events, delegates and object lifetime
5. Constants, fields and versioning across assemblies
6. Interfaces, generics, enums
7. Exceptions
8. Nullability
9. Where Richter and the C# community disagree

## 1. Value types vs reference types

| | Reference type (`class`) | Value type (`struct`) |
|---|---|---|
| Lives | on the managed heap, with a type-object pointer and sync-block header | inline: on the stack, or inside the containing object or array |
| Assignment copies | the reference | every field |
| Default | `null` | all fields zeroed; there is no "unset" |
| Inheritance | yes | none; value types are sealed |
| Collected by GC | yes | no, unless boxed |

Where this bites in gameplay code:

- A `struct` returned from a method or passed as an argument is copied field by field. A 64-byte struct going through five call frames is five copies.
- Reading a `struct` out of a `List<T>` through the indexer gives you a copy. `list[i].Health -= 1` does not compile for a mutable struct field for exactly this reason, and where it does compile (on a local) it quietly edits the copy.
- A `readonly` field of struct type is defensively copied on every method call made against it, unless the type is a `readonly struct`.

### When to declare a struct

All of these have to hold:

1. It behaves like a primitive: simple and immutable. No member changes its own fields; prefer `readonly struct` and `readonly` fields.
2. It does not need to inherit from anything.
3. Nothing will derive from it.

And one of these:

4. Instances are small, roughly 16 bytes or less.
5. Instances are large but never passed as parameters or returned from methods, because they live in an array you index in place.

If a struct is a dictionary key or gets compared often, override `Equals` and `GetHashCode`. The defaults on `ValueType` go through reflection and are slow.

Good Unity structs: ids, small typed values (`Damage`, `Health`, `TileCoord`), event payloads consumed on the spot. Bad Unity structs: anything mutable, anything with a lifecycle, anything you keep passing by `ref` to keep it in sync.

## 2. Boxing: the allocation you did not write

Boxing turns a value type into a reference type: allocate on the heap, copy the fields in, hand back the address. It is a heap allocation and a copy, and the compiler emits it without telling you. Unboxing is cheap on its own, but almost always followed by another copy.

Where it hides in Unity code:

- Putting a value type into anything typed `object`: non-generic collections, `params object[]`, `string.Format`, `Debug.Log` with a boxed argument.
- Calling an interface method on a struct through the interface (`IComparable`, `IEquatable`, a custom `IState` implemented by a struct).
- `Enum.HasFlag`, which has historically boxed both operands on Unity's runtimes. Use `(flags & Flag.X) != 0` on hot paths.
- Enums and other value types as dictionary keys on older Mono, where the default equality comparer fell back to a boxing implementation. Pass an explicit `IEqualityComparer<T>` if you are on an old runtime or a profile says so.
- `foreach` over an `IEnumerable<T>` boxes the enumerator. `foreach` over a concrete `List<T>` or an array does not, because the struct enumerator is used directly.
- Calling `Equals(object)`, `ToString()` or `GetHashCode()` on a struct that does not override them.
- `object`-typed event args, `SendMessage`-style APIs, and anything driven by reflection.

The cures: generics with proper constraints, `IEquatable<T>`, iterating over the concrete type, overriding `Equals` and `GetHashCode`, and the numeric overloads of formatting APIs (`TMP_Text.SetText` takes numbers without going through `string.Format`).

## 3. Where per-frame garbage comes from

In the order it turns up in real projects:

1. **Closures.** A lambda that captures a local or `this` allocates a closure object and a delegate every time it is created. `list.Sort((a, b) => a.Order - b.Order)` inside `Update` allocates twice per frame. Cache the delegate in a `static readonly` or instance field, or use a method group with no captures.
2. **`yield return` iterators.** Every coroutine start allocates the state machine, and every `new WaitForSeconds(1f)` allocates. Cache yield instructions in fields: `private static readonly WaitForSeconds oneSecond = new(1f);` is safe to share because `WaitForSeconds` holds no state. `WaitUntil` and `WaitWhile` take a delegate, so they have the closure problem above.
3. **LINQ.** Every operator allocates an enumerator and usually a closure. Keep it off the per-frame path. It is fine in loading, saving and editor code.
4. **Strings.** They are immutable, so every concatenation, interpolation, `ToString()` and `Substring` is a new object. Use `StringBuilder` for building, cached strings or the numeric `SetText` overloads for UI, and `StringComparison.Ordinal` for comparisons (faster, and free of culture surprises).
5. **Boxing**, covered above.
6. **Collections that grow.** `List<T>` doubles its backing array and drops the old one. Give it a capacity up front; reuse a field and `Clear()` instead of `new`.
7. **`params` arrays.** Every call allocates, and in some overload sets that includes calls with zero arguments.
8. **Unity APIs that return arrays**: `GetComponents`, `Physics.RaycastAll`, `Mesh.vertices`, `GameObject.FindGameObjectsWithTag`. Use the `NonAlloc` or buffer overloads on hot paths.

**Deterministic disposal.** Anything holding a native or unmanaged resource (`NativeArray`, a `Texture2D` you created, `ComputeBuffer`, `CancellationTokenSource`, file handles) implements `IDisposable` and is used with `using`. The GC is not a resource manager. Finalizers, where they exist at all, run at an unpredictable time and cost an extra collection cycle.

## 4. Events, delegates and object lifetime

A delegate holds a strong reference to its target. So as long as an object has one of its methods registered with an event, that object cannot be collected.

That is the CLR-level reason behind "never subscribe without unsubscribing". The leak is not a Unity quirk; it is how delegates work. It also means a `Dispose` implementation should unregister every event the object subscribed to.

In practice:

- Declare an `event`, not a public delegate field. A public `Action Fired;` lets any caller raise it and, worse, set it to `null` and wipe everyone else's subscriptions. The `event` keyword limits outside code to `+=` and `-=`.
- Raise it with `fired?.Invoke(args)`. A null check followed by a call has a race, and reads worse.
- You cannot `-=` a lambda you wrote inline. `x.Fired += () => ...` creates a new delegate object each time, and the one you try to remove is a different object. Keep a field, a named method, or an `IDisposable` subscription handle.
- Static events are the sharpest edge. The subscriber is rooted for the life of the domain, which in Unity often now survives entering and leaving play mode. Avoid them. If one is unavoidable, unsubscribing is mandatory and there is an explicit reset path.
- Prefer many small typed events to one `object`-payload event bus. The payload boxes and every caller casts.

## 5. Constants, fields and versioning across assemblies

`const` is compile-time. Its value is copied into every assembly that reads it. If `Project.Core` declares `public const int MaxPlayers = 4;` and `Project.Gameplay` uses it, the literal `4` is baked into `Project.Gameplay`. Change it, and any assembly that was not recompiled keeps the old value. Unity recompiles `.asmdef`s together, so this rarely bites inside a project. It bites with precompiled DLLs, packages and shipped plugins.

`static readonly` is read at runtime, so consumers always see the current value. Use it for anything that could plausibly change and for anything that crosses an assembly or package boundary. Keep `const` for values that are true by definition (`SecondsPerMinute = 60`).

`static readonly` is also the only option for values that are not compile-time constants: `Animator.StringToHash("Run")`, `Shader.PropertyToID`, a cached `WaitForSeconds`.

`readonly` on an instance field means "assignable only in the constructor or initializer". It says nothing about the object it points to; a `readonly List<T>` is still mutable. For a genuinely read-only surface, expose `IReadOnlyList<T>`.

## 6. Interfaces, generics, enums

Generic collections over non-generic ones, always: no boxing, type safety at compile time, fewer casts.

Constrain generics (`where T : class`, `where T : struct`, `where T : IThing`). An unconstrained `T` compared with `==` or `Equals` will box. `EqualityComparer<T>.Default` and `IEquatable<T>` are how dictionaries and sets compare without boxing.

Explicit interface implementation hides a member from the class's public surface, which is useful for keeping an infrastructure interface (`ISaveable`, `IPoolable`) out of the type's everyday API. Calling it needs a cast to the interface, and if the type is a struct, that cast boxes.

Enums are named integer constants. Any integer of the underlying type can be cast into one, valid member or not, so never assume an enum value is in range. A `switch` over an enum needs a `default` that fails loudly.

`[Flags]` enums use explicit powers of two and include a `None = 0`. Combine with `|`, test with `&`.

## 7. Exceptions

An exception is for a situation the caller could not reasonably have prevented. Conditions you can test for, such as no target in range, an empty inventory or a missing optional component, are tested, not thrown.

Throwing is expensive (stack capture, unwinding), so catching in a loop is a performance bug and a design bug at once.

Never swallow. A `catch` either handles the situation properly, adds context and rethrows (`throw;`, not `throw ex;`, which resets the stack trace), or does not exist.

Cleanup goes in `finally` or a `using`, because that runs on the exception path too. One Unity caveat: disabling or destroying a `GameObject` stops its coroutines without running their `finally` blocks, so do not rely on `finally` for coroutine cleanup.

A method that throws halfway through must not leave the object in a state where the next call misbehaves. Validate first, mutate after.

Do not let an exception escape into Unity's callback machinery on a per-frame path. One `Update` that throws every frame will eat the frame budget and flood the log.

## 8. Nullability

`?.`, `??` and `is null` test for real CLR null. `UnityEngine.Object` overrides `==` to also report destroyed-but-not-yet-collected objects as null, so those operators skip that check and hand you a dead object. For anything deriving from `UnityEngine.Object`, use `== null` or `if (obj)`. For plain C# objects, use whatever reads best.

Nullable value types (`int?`) are `Nullable<T>`, a struct with a flag. They box to either a boxed `T` or a true null, never to a boxed `Nullable<T>`.

If the project enables nullable reference types (`#nullable enable`), follow it everywhere. If it does not, do not introduce annotations in one file only.

## 9. Where Richter and the C# community disagree

*CLR via C#* prefers the framework type names (`Int32`, `Single`, `String`) to the language keywords and argues the keywords mislead. The C# and Unity convention is the keywords (`int`, `float`, `string`), and consistency with the ecosystem wins. Use the keywords, and use the framework names only where the type itself is the subject (`Int32.TryParse` and `System.Single.Epsilon` are fine).
