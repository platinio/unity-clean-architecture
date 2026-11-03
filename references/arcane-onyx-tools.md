# Arcane Onyx tools: detect, install, set up

Read this when a design needs Zenject, Hermes or the ScriptableObject database and you must tell whether
the project has it, or install it. Nothing here is needed while the tool is already in place.

## Detection

Check the assembly definition's **name field**, not the file name: an asmdef's internal name can differ
from its file. Where a tool adds a scripting define, the define is the cheaper check.

| Tool | Runtime asmdef name | Define | Note |
|---|---|---|---|
| Zenject (vendored, with Static Installers) | `Zenject` | `MODULE_ZENJECT_EXIST` | `[StaticInstaller]` lives in the `Zenject` namespace |
| Hermes | `Hermes.Runtime` | `HERMES_EVENTS_GENERATED` says events were generated, not that Hermes exists | generated code under `Assets/Hermes.Generated` |
| ScriptableObjectDatabase | `ArcaneOnyx.ScriptableObjectDatabase` | `MODULE_SCRIPTABLE_OBJECT_DATABASE_EXIST` | |

## Installing

**Submodule by default.** Submodules exist to be edited; anything the project might need to fix or extend
goes in as one. A unitypackage from the repository's Releases page is for a throwaway demo that will never
touch the tool. Say which case applies.

- Follow the project's existing submodule paths. A project with none uses `Assets/ArcaneOnyx/<Name>`.
- `git submodule add <url> <path>` on the feature branch. The pointer is committed only when commits are
  asked for.
- Add the dependencies listed below the same way, then do the post-install steps through the Editor,
  recompile, and check the console before any code uses the tool.
- A unitypackage import needs the Editor: `AssetDatabase.ImportPackage(path, false)` through `script.eval`.

### Zenject

- Repository: https://github.com/platinio/Unity-Zenject (private; sign in). Container API docs:
  https://github.com/Mathijs-Bakker/Extenject
- Depends on UnityExtensions (for `[AutoAssetGeneration]`).
- After install, one scene object: a `SceneContext` with a `StaticInstaller` component that reads
  `Assets/Installers/StaticInstallerManifest.asset`. The manifest is generated and rebuilt on every
  reload; never edit it by hand. A project without the convention lists its installers on the
  `SceneContext` instead.
- A module installer: `[AutoAssetGeneration("Installers/Static", "<Name>StaticInstaller")]` plus
  `[StaticInstaller(StaticInstallerExecutionOrder.<Order>)]` on a `ScriptableObjectInstaller`. On the
  next reload the asset is created and registered. Orders: `NonImportant` (utility, no dependency on
  other modules), `Normal`, `Important` (overrides `Normal`), `Override` (runs last). The generated
  installer asset is a real asset: commit it.

### Hermes

- Repository: https://github.com/platinio/Unity-HermesEventGenerator
- Depends on ScriptableObjectDatabase, UnityExtensions and Zenject, installed the same way.
- After install: a scene object with `SceneGameEvents` and `GameEventDispatcher` (one per scene). In
  **Window → Arcane Onyx → Hermes** create the event as a code identifier (`OnMoraleChanged`), add its
  arguments and the namespaces their types need, then **Regenerate**; the `HERMES_EVENTS_GENERATED`
  define appears once generation succeeds. Project Settings → Hermes Settings holds the output paths,
  the Visual Scripting toggle and `extraAssemblyReferences` for generated assemblies that need game
  types. Regenerate from code when the window is not available:
  `ArcaneOnyx.GameEventGenerator.GameEventDefinitionEditorWindow.GenerateEvents()`.
- Every event on the dispatcher follows `On<Name>GameEvent.Raise(...)`, `.AddListener(h)`,
  `.RemoveListener(h)`. Without Zenject, `ServicesContainer.Resolve<ISceneGameEvents>()` gives the same
  object.
- Debugging: in play mode, select the event in the Hermes window and **Add Event Trigger Component** to
  fire it by hand; `GameEventDispatcher.OnGameEventRaisedEvent` fires for every event.

### ScriptableObjectDatabase

- Repository: https://github.com/platinio/Unity-ScriptableObjectDatabase. No dependencies.
- An item is a `ScriptableItem` subclass; a database is `ScriptableDatabase<TItem>` with
  `[CreateAssetMenu]`. Items are sub-assets inside the database file. Three one-line editor classes in
  the Editor assembly give the window and inspectors: `DatabaseEditorWindow<TDatabase, TItem>`,
  `ScriptableDatabaseEditor<TWindow, TDatabase, TItem>`, `ScriptableItemDefaultEditor<TWindow, TDatabase, TItem>`.
- Reference an item from any inspector with
  `[SerializeField, ScriptableItemDatabaseSelector(typeof(MyDatabase))] private MyItem item;`.
- Runtime: `database.GetItemByName("Inspired")`, `database.GetItem(savedId)`, `database.Items`. IDs are
  GUID-based; **Migrate IDs** in the window upgrades legacy numeric IDs.
- A ScriptableObject is shared: never mutate an item at run time. Copy to a plain runtime state object.
