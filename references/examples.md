# Before and after

Every pair below is a real correction from a review. The rule numbers are the `architecture` skill's.

## Contents

- Renames
- Method shape
- An entry method that tells the story
- Comments
- Asking an object which class it is
- Two limits, seen in practice

## Renames

| Before | After | Rule |
|---|---|---|
| `ProcessCrossings` | `HandleAttackWindows` | 1: meaning, not technique |
| `Active`, `CancelAttack` | `HitWindow`, `ComboWindow` | 2: precise, not generic |
| `Arm(attack, target)` / `Disarm()` | `HitWindowOpened(attack, target)` / `HitWindowClosed()` | 3: no jargon |
| `IHitWindowSink`, `IDisplacementSink` | `IHitWindowListener`, `IWarpMover` | 3: no pattern slang |
| `armed`, `cancelOpen` | `IsHitWindowOpen`, `IsComboWindowOpen` | 4: booleans are questions |
| `lastPicked`, `previous`, `t` | `lastAttackPickedAtNode`, `previousTime`, `currentTime` | 6: long and clear |
| `from`, `to`, `span`, `fraction` | `frameStart`, `frameEnd`, `timeLeftInWindow`, `shareOfDistance` | 7: name the parts of a calculation |
| `_config` | `config` | 8: no encodings |
| `ResolveInput`, `CombatContext` | `ComboSituation`, `CombatFacts` | 1 and 2: meaning |
| `publisher.Publish(target, attack)` | a `CombatFactsUpdater` that measures and publishes facts | 1: the reader could not tell what was published or why |
| `DeadAheadSine = 0.1f` | `deadAheadAngle = 6` (degrees) | 13: store a value in the unit a person tunes |

## Method shape

| Before | After | Rule |
|---|---|---|
| `TickIdle` and `TickPlaying`, each with the same "check, then start" block | one `Tick` whose body reads as steps, the shared block in one method | 10 and 12 |
| `HandleAttackWindows(attack, -1f, 0f, position)` | `HandleWindowsStartingAtZero(attack, position)` | 13: magic values |
| `Finish(interrupted, stopDriver)` | `EndCurrentAction()` and `EndCurrentActionAndGoIdle()` | 14: no flag parameters |
| five `= false` lines repeated in two methods | `CloseAllWindows()` | 17: one owner per piece of state |
| `if (!IsRecording \|\| node == null) return;` opening eight recorder methods, unseen by a pass that rewrote all eight | `CanRecord(node)`, or a stated decision to keep the copies; found only once guards were counted over the files, not the diff | 12 and 18 |

## An entry method that tells the story

```csharp
public void Tick(float deltaTime, Vector3 position, bool canStartFromIdle)
{
    if (isPlaying)
    {
        AdvanceCurrentAction(deltaTime, position);
    }
    else
    {
        AdvanceIdleTime(deltaTime);
        RestartComboAfterLongIdle();
    }

    if (TryStartActionFromPress(position, canStartFromIdle))
    {
        return;
    }

    if (isPlaying && HasCurrentActionEnded())
    {
        EndCurrentActionAndGoIdle();
    }
}
```

A reader stops here and knows what a tick does. Each step is a private method below, in this order.

## Comments

Kept, because the code cannot say why:

```csharp
// Moves a share of the remaining distance each frame, so the character arrives exactly as the
// window closes whatever the frame rate. A fixed step overshoots at low frame rates.
```

Kept, because an outside limit forces an odd approach:

```csharp
// Reads the sensor on a worker thread because the device driver blocks for up to 40 ms;
// a main-thread read drops frames on the target hardware.
```

Dropped, because the name already says it:

```csharp
// Picks which attack a node plays.
private AttackDefinition PickAttack(ChainNode node)
```

Dropped at the time as a restatement of the class name. Under rule 22 a public type that other systems use may keep a summary like this when it says more than the name does, as long as it stays within three lines:

```csharp
/// <summary>
/// Measures this character's combat facts each tick and mirrors them onto its agent variables.
/// </summary>
public sealed class CombatFactsUpdater : CharacterComponent
```

Dropped, because it made a claim about another file that nothing checked:

```csharp
/// Static and allocation-free so it can be tested in EditMode with plain vectors.
public static class GroupFraming
```

There was no test. The claim became `GroupFramingTests`, and the sentence went.

Dropped, because each one was doing a name's or a test's job. This reached two pull requests past
a self-review and an independent review:

```csharp
/// <summary>A strike that passed the land check, as its target receives it.</summary>
public readonly struct HitInfo
{
    public readonly AttackDefinition Attack;

    /// <summary>
    /// From the attacker toward the target, flat and of length one. Zero when the attacker
    /// stands on the target.
    /// </summary>
    public readonly Vector3 Direction;
}
```

```csharp
public readonly struct HitInfo
{
    public readonly AttackDefinition Attack;
    public readonly Vector3 DirectionFromAttackerToTarget;
}
```

- The summary on the type made a claim about another file: that a land check had passed. The
  constructor was public, and the tests built a `HitInfo` with no check at all.
- The comment on the field said what the field holds. That is the name's job.
- "Flat, of length one, zero when standing on it" was a guarantee. Two tests of the code that
  makes the value already asserted it, so the comment only repeated a test, and unlike the test it
  could not fail.

Both comments were kept because they added information. Adding information is not the test.

## Asking an object which class it is

The hit switch must do nothing while the character is dead or lying on the floor. It found out by
asking the state machine which class the current state was:

```csharp
bool isDead = stateMachine.Current is DeadState;
if (isDead)
{
    return;
}

bool isOnTheFloor = stateMachine.Current is KnockedDownState;
if (isOnTheFloor)
{
    return;
}
```

The attack switch did the same with `currentState is LocomotionState || currentState is AttackingState`.

Every one of these lines passes the naming rules: each `if` reads as a sentence. That is what made
them hard to see. The switch had become the keeper of the list of states that count. A new state that
must also be left alone means finding every such line and editing it (SOLID O), and the switch only
works for the classes it names (L).

Now each state answers for itself. `ICharacterState` gained two questions, `CanBeInterrupted` and
`IsFreeToAct`. A reaction state answers that it can be interrupted, and the floor and death override
that to say they cannot:

```csharp
public override bool CanBeInterrupted => false;
```

and the switch asks, without knowing who it is asking:

```csharp
if (!stateMachine.Current.CanBeInterrupted)
{
    return;
}
```

A new state gives its own answer in its own file, and no switch changes.

## Two limits, seen in practice

- **The user's own names win.** They chose `Window.IsOpen(previousTime, currentTime)`. A subagent
  renamed it to `OpensBetween`, and it had to be reverted.
- **Explain simply first.** "The runner arms the sink on the crossing" stopped the conversation.
  "When the hit window opens, the runner tells the listener which attack and target" did not.
