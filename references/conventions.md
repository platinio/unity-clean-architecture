# Conventions: naming, layout, assemblies

Read this when creating a type, a file or an assembly, or when a review needs a convention to point at. The repository's existing conventions outrank these. Use these where the repository has none, and say that is what you are doing.

## Naming

| Element | Rule | Example |
|---|---|---|
| Class, struct, enum | `PascalCase`, a noun | `EnemySpawner`, `DamageInfo` |
| Interface | `I` plus `PascalCase` | `IDamageable`, `IAudioService` |
| Method | `PascalCase`, a verb | `TakeDamage`, `TrySpawn` |
| Property | `PascalCase` | `MaxHealth` |
| Event | `PascalCase`, past tense | `Damaged`, `Died`, `ScoreChanged` |
| Event handler | `On` plus the event | `OnDamaged` |
| Private field, serialized or not | `camelCase`, no leading underscore | `currentHealth`, `[SerializeField] private float moveSpeed;` |
| Constant, `static readonly` | `PascalCase` | `MaxPlayers`, `RunningHash` |
| Local, parameter | `camelCase` | `deltaTime` |
| Boolean | a question: `Is`, `Has`, `Can`, `Should` | `IsDead`, `HasAmmo`, `CanFire`, `ShouldRespawn` |
| Async method | `Async` suffix | `ReloadAsync` |
| Enum members | `PascalCase`, singular type name | `WeaponKind.Shotgun` |
| Config asset type | `Definition` or `Config` suffix | `EnemyDefinition` |
| Abstract base | named for the concept, no `Base` prefix | `Ability`, not `BaseAbility` |

A private field and its parameter share a name; `this.speed = speed` disambiguates. The underscore prefix is a convention this plugin does not use.

`Manager`, `Helper`, `Utils` and `Controller` are not names on their own. `GameManager` manages what? Split it into the things it does: `ScoreCounter`, `WaveScheduler`, `MatchFlow`. A suffix that carries a real meaning is fine and worth using consistently: `Service` (an injected capability), `Factory`, `Pool`, `Repository`, `View`, `Presenter`, `State`, `Installer`, `Spawner`.

Only universally understood abbreviations (`id`, `ui`, `vfx`). `enemyCount`, not `enmCnt`. Identifiers, comments and commit messages are in English.

## File layout

One type per file, and the file is named after the type. A small helper type (an `enum`, a `readonly struct` payload) may live beside its only consumer. Inside a class, in this order: constants and `static readonly` fields; serialized fields; other private fields; properties; events; Unity lifecycle methods in call order (`Awake`, `OnEnable`, `Start`, `Update`, `OnDisable`, `OnDestroy`); public methods; private methods; nested types.

## Project structure and namespaces

Your code sits under one root, apart from imported assets and plugins. The leading underscore sorts it above imported packages in the Project window.

```
Assets/
  _Project/
    Scripts/
      Bootstrap/   Core/   Data/   Gameplay/   UI/   Integrations/   Editor/
    Art/  Audio/  Prefabs/  Scenes/  Configs/
  Plugins/         third-party, never restyled or refactored
```

`Bootstrap` holds composition roots and entry points; `Core` holds services, pooling, events and save; `Integrations` wraps third-party SDKs; `Editor` is editor-only tooling. Inside `Gameplay`, organize by feature (`Weapons/`, `Enemies/`, `Inventory/`), not by technical kind (`Interfaces/`, `Abstracts/`). Feature folders keep a change in one place.

The namespace mirrors the folder path under the scripts root: `Assets/_Project/Scripts/Gameplay/Combat/Weapon.cs` is `namespace Project.Gameplay.Combat`. Every type has a namespace; the global namespace collides with imported assets sooner or later. File-scoped namespaces where the C# version allows.

## Assembly definitions

One `.asmdef` per layer. Layer violations then become compile errors instead of matters of discipline, and recompiles get faster.

| Assembly | References |
|---|---|
| `Project.Core` | external packages only |
| `Project.Data` | `Core` |
| `Project.Gameplay` | `Core`, `Data` |
| `Project.UI` | `Core`, `Data`, `Gameplay` |
| `Project.Integrations` | `Core` plus vendor SDKs |
| `Project.Bootstrap` | all of the above |
| `Project.Editor` | all, with `includePlatforms: ["Editor"]` |
| `Project.Tests` | the assemblies under test plus the test framework |

Editor code lives only in the Editor-only assembly. If something needs a backwards reference to compile, the dependency direction is wrong; fix that, not the asmdef.

## Tests

Tests live in a `Tests` folder with their own `.asmdef`, EditMode by default; PlayMode only when the engine lifecycle or physics is part of what is being tested. Test plain C# logic: damage math, state transitions, inventory rules, save migration. Name each test `Method_Scenario_Expected`: `TakeDamage_WhenAlreadyDead_DoesNotChangeHealth`. When refactoring live logic, write the test before the refactor; it is the cheapest safety net available.

## Style

- `sealed` on classes not designed for inheritance, which is most MonoBehaviours. `readonly` on fields that never change after construction.
- Write `private` explicitly. `var` where the type is obvious from the right-hand side.
- Braces on multi-line blocks; a single-line `if (x) return;` is fine.
- No `#region`. It usually hides a class that is too big.
- A `/// <summary>` of one to three lines on a public type or member other systems call. None on private members. Other comments say why, not what.
- `TODO` only with an owner and a reason.

## Version control

- A `.cs` file and its `.meta` are committed together. A missing `.meta` breaks every reference to the file.
- `Library/`, `Temp/`, `Logs/`, `obj/`, build output and generated `.csproj`/`.sln` files are ignored. Start from a standard Unity `.gitignore`.
- Git LFS for large binary assets. Scenes and prefabs as text, with locking if the team wants it; YAML merge conflicts are a real cost.
- Commit messages are short and imperative and describe intent, not mechanics.
