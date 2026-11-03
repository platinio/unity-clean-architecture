# SOLID in Unity code

The five questions themselves live in the architecture skill. This file is what each one looks like in Unity code, with a worked example and the caveat that stops it from being applied everywhere.

## Single Responsibility

A class has one reason to change. Describe it in one sentence with no "and". The usual Unity violation is a `PlayerController` that reads input, moves the character, fires weapons, updates the HUD, plays audio and writes the save file.

| Class | Owns |
|---|---|
| `PlayerInputReader` | turns raw input into intents (`MoveInput`, `IsFirePressed`) |
| `PlayerMovement` | moves the character from an intent |
| `Weapon` | firing, ammo, reload timing |
| `Health` | damage, death, publishes events |
| `PlayerHud` | subscribes to `Health` and `Weapon` and renders |
| `SaveService` | persistence |

Signs it is time to split: the `using` list spans UI, physics and audio; every new feature edits the same file; the name is `Manager` or `Controller` with nothing in front of it. Do not overshoot. A class per thought is as bad as a god class; a healthy class owns coherent state and a handful of methods that operate on it.

## Open/Closed

Adding a variant should add a class or an asset, not an edit to existing code. This pays off where variants keep arriving; with one fixed variant, a `switch` is more honest than an abstraction.

```csharp
// Every new effect edits this method
public void ApplyEffect(EffectType type, Character target)
{
    switch (type) { case EffectType.Poison: /* ... */ break; case EffectType.Burn: /* ... */ break; }
}

// Polymorphism as a Type Object: a new effect is a new asset
public abstract class StatusEffect : ScriptableObject { public abstract void Apply(Character target); }

public sealed class PoisonEffect : StatusEffect
{
    [SerializeField, Min(0)] private int damagePerTick = 5;
    public override void Apply(Character target) => target.Health.TakeDamage(damagePerTick);
}

public void ApplyEffect(StatusEffect effect, Character target) => effect.Apply(target);
```

## Liskov Substitution

A subtype works wherever the base type is expected, without surprising the caller. Overrides extend the base behaviour rather than replacing it. Unlike the other principles, this one has a checklist:

| Rule | In practice |
|---|---|
| Parameter types may widen, never narrow | base `Feed(Cat c)`, override `Feed(Animal a)` is fine; `Feed(BengalCat c)` breaks callers |
| Return types may narrow, never widen | base `BuyCat(): Cat`, override returning `BengalCat` is fine; returning `Animal` breaks callers |
| No new exception types | callers only guard against what the base declares |
| Do not strengthen preconditions | if the base accepts any `int`, the override does not reject negatives |
| Do not weaken postconditions | if the base guarantees resources are released, so does the override |
| Preserve the base class invariants | the conditions under which the object still makes sense |
| Do not reach into state the parent relies on | side doors into the parent's fields break its own logic |

C# enforces the first three at compile time; the last four are on you. Game-specific violations: an override that throws `NotSupportedException` ("this enemy cannot move"); a subclass that breaks on zero damage where the base accepted any value; `InvulnerableHealth : Health` whose `TakeDamage` does nothing while every caller assumes health decreases. Each says the hierarchy is wrong. Split into narrow interfaces (`IDamageable`, `IMovable`) and compose. Invulnerability is a state or a modifier, not a subclass.

## Interface Segregation

Several narrow interfaces beat one wide one. They suit Unity: a raycast hit does `GetComponent<IDamageable>()` and neither knows nor cares whether it hit an enemy, a barrel or a door.

```csharp
// A wall that cannot move is forced to implement Move
public interface IEntity { void Move(Vector3 delta); void TakeDamage(int amount); void Interact(); void Save(); }

// Each caller asks for exactly what it needs
public interface IDamageable   { void TakeDamage(int amount); }
public interface IInteractable { void Interact(Character source); }
public interface IMovable      { void Move(Vector3 delta); }
```

## Dependency Inversion

Gameplay depends on an interface it owns; the vendor implementation depends on that same interface. The violation is `SomeVendorAudioSdk.Instance.Play("shot")` sitting inside `Weapon.Fire`.

```csharp
// Gameplay owns the interface; the composition root picks the implementation
public interface IAudioService { void Play(AudioId id); }

public sealed class Weapon : MonoBehaviour
{
    private IAudioService audio;
    public void Construct(IAudioService audio) => this.audio = audio;
    private void Fire() => audio.Play(AudioId.Shot);
}
```

Ads, IAP, analytics and attribution go through interfaces like this, so a vendor swap is one class and a dev build can run stubs. Do not invert everything. Depending on `Transform`, `Rigidbody` or `Mathf` is depending on the engine, and that is fine. Invert what actually gets substituted: services, data sources, strategies.
