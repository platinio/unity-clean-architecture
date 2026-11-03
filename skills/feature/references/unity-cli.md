# The Unity CLI, as the feature skill uses it

Read this before the first Editor call of a run. Every command below was run against a live Editor when
this file was written; the output shapes and the traps are the ones seen. The `unity` CLI drives a running
Editor through the Pipeline package's server; nothing here opens or closes the Editor.

## Contents

- Every call names the project
- Output you can parse
- Preflight: is the Editor there
- A red project means no CLI at all
- Recompile
- Tests
- Player build
- Console, scripts, scenes, play mode, captures
- Timeouts and dialogs

## Every call names the project

Pass `--project-path <main checkout>` on every `unity command`, `unity recompile` and `unity job` call. The
CLI finds the Editor from the current directory when the flag is absent, and from a worktree or any other
folder it answers "no connected Editor" even while the Editor is up. The path is the project's main
checkout, never a linked worktree.

## Output you can parse

- `--format json` is the only output a script should read. It wraps the result in an envelope,
  `{ success, command, data: { command, parameters, result, target }, errors[], warnings[] }`: the command's
  own answer is `data.result`, and `errors[].message` carries the reason on failure.
- Human-format output, `--result-only` included, ends with a hint line in angle brackets that the CLI appends
  for agents, so it is not valid JSON and a naive "last token" grab picks up the hint. Use it only for reading
  by eye.

## Preflight: is the Editor there

```bash
unity status --no-banner
```

A table, one row per connected Editor: `port  state  project  version  pid`. The run needs a row whose
`project` is this project's path and whose `state` is `ready`. For the detailed state:

```bash
unity command --no-banner --project-path "<project>" --format json editor.status
```

`data.result`:

```json
{ "status": "ready", "compiling": false, "domainReloadInProgress": false, "playMode": "stopped", "projectPath": "...", "unityVersion": "6000.1.15f1" }
```

`status` is also `playing` while a PlayMode test runs or the user is in play mode; wait for `ready` before
launching anything.

## A red project means no CLI at all

The Pipeline server does not start while there are compile errors: `unity status` shows no row and every
command fails. Keep the project compiling. If it goes red, fixing that is the only task until it is green,
and if you cannot, stop and report: a feature cannot be finished without a compiler.

## Recompile

```bash
unity recompile --no-banner --project-path "<project>" --timeout 300
```

Prints a table of compile errors (`severity  code  file  line  column  message`); an empty table is a clean
compile. Returns in about a second when scripts are already up to date. After `script.create`, the new type
exists only once a recompile has completed: recompile, then `script.recompile_status` (`idle | triggered |
compiling | completed | up_to_date`), then `script.attach`.

## Tests

Launch a run asynchronously; the command returns at once and the Editor writes the result when the run ends.

```bash
unity command --no-banner --project-path "<project>" --format json test.run --mode editor --async_tests true
unity command --no-banner --project-path "<project>" --format json test.run --mode editor --async_tests true --filter StaminaMeterTests --filter_type testName
unity command --no-banner --project-path "<project>" --format json test.run --mode playmode --async_tests true
```

- `--mode editor` and `--mode playmode` are two separate runs. `--mode all` has returned EditMode only.
- `--filter <text>` with `--filter_type testName | assembly | category`; `--include_explicit true` for
  `[Explicit]` tests. A filter that matches nothing usually means the new test is not compiled yet.
- Before a PlayMode run, `editor save_all`, unless the open scene is untitled: saving an untitled scene
  raises a Save Scene dialog that blocks the Editor.

**Reading the result.** The Editor writes `<project>/Temp/pipeline_test_status.json` when the run completes;
while the run is in progress the file is absent (or still the previous run's) and `Temp/pipeline_test_request.json`
exists. Poll every 10 s. The same JSON comes back as `data.result` of `--format json test.status`, which
returns the last completed run with no freshness marker, so confirm you are reading your run: a test name you
just added, or a `total` that changed. The status file is plain JSON and the easier read.

```json
{ "status": "completed", "duration": 179.41,
  "summary": { "total": 2269, "passed": 2260, "failed": 6, "skipped": 3, "inconclusive": 0 },
  "results": [ { "FullName": "Namespace.Class.Method", "Status": "Passed", "Duration": 0.02, "Message": null, "StackTrace": null } ] }
```

`results` holds every test; a full suite is thousands of entries. Never print it whole. Summarise:

```bash
python -c "import json,io,sys; d=json.load(io.open(sys.argv[1],encoding='utf-8')); print(d['status'], d['summary']); [print('FAILED', r['FullName'], '-', (r['Message'] or '').splitlines()[0] if r['Message'] else '') for r in d['results'] if r['Status']=='Failed']" "<project>/Temp/pipeline_test_status.json"
```

A full EditMode suite of about 2,300 tests took three minutes. Give the Bash call that waits a `timeout` of
600000 or more.

**Do not use `--detach` and `unity job wait` for tests or builds.** Detached jobs do not survive a domain
reload, and a test run and a player build both trigger one; the job disappears and `job wait` reports
"Job Not Found" while the Editor is still running the work. The async launch plus the status file is the
path that holds.

## Player build

```bash
unity command --no-banner --project-path "<project>" --format json build.run --confirm true --outputPath "Builds/feature-gate/FeatureGate.exe"
```

- Without `--confirm true` the command refuses: "this triggers a player build. Pass confirm=true to build, or
  dry_run=true to validate without building." A `dry_run` is not a build and is never reported as one.
- The output path is relative to the project root, outside `Assets/`, in a git-ignored folder (`Builds/` here).
  Pass `--target <BuildTarget>` for a target other than the active one, and `--scenes` as a JSON array
  string (`'["Assets/Demos/Foo/Foo.unity"]'`) to add the demo scene to the project's enabled scenes; a
  comma-separated string is silently ignored and the default scenes build.
- `editor save_all` first (unless the scene is untitled): a build reads scenes from disk.

The command returns at once. Poll `build.status` every 15 s; `status` is `idle | queued | building |
completed`. Give the waiting Bash call a `timeout` of 1200000 or more.

```bash
unity command --no-banner --project-path "<project>" --format json --timeout 30 build.status
```

The completed payload is the whole BuildReport, 2.8 MB for a mid-sized project. Never print it; write it to
a file and print only the summary. Only `result: "Succeeded"` with `totalErrors: 0` from a real build is a
pass. A build
makes the Editor recompile afterwards; wait for `editor.status` to read `ready` and `compiling: false`
before the next test run. Warning counts are not comparable between builds (a cold build recompiles more);
read the warnings for ones that name your types.

### Build report shape

`data.result` of `build.status`, with the large lists left out:

```json
{ "status": "completed", "buildId": "build_51c01ac4cad1", "result": "Succeeded", "platform": "StandaloneWindows64",
  "outputPath": "<project>/Builds/feature-gate/FeatureGate.exe", "totalSizeBytes": 123028264, "buildTimeMs": 104448,
  "totalWarnings": 79, "totalErrors": 0,
  "errors": [], "warnings": [ { "message": "..." } ], "buildSteps": [ { "name": "Build player", "durationMs": 104448, "depth": 0, "messages": [] } ],
  "files": [ "...254 entries..." ], "packedAssets": [ "...8 entries..." ] }
```

`status` is `idle | queued | building | completed`; before `completed` only `status` is present. A player
build of a mid-sized project took 105 s of build time and about two and a half minutes wall clock including
the recompile afterwards. Summarise with:

```bash
unity command --no-banner --project-path "<project>" --format json --timeout 120 build.status > "<scratchpad>/build-status.json"
python -c "import json,io,sys; r=json.load(io.open(sys.argv[1],encoding='utf-8'))['data']['result']; print(r['status'], r.get('result'), 'errors', r.get('totalErrors'), 'warnings', r.get('totalWarnings'), r.get('platform'), r.get('outputPath')); [print('ERROR', e.get('message','')[:300]) for e in r.get('errors',[])]" "<scratchpad>/build-status.json"
```

## Console, scripts, scenes, play mode, captures

| Command | Use |
|---|---|
| `console.get --tail 50 --level error` | the last console entries; `--since <cursor>` follows from a point |
| `console.clear` | clear before a run so what you read is yours |
| `script.create`, `script.attach --type <TypeName>` | create a script, add a component; attach only after a completed recompile |
| `script.recompile`, `script.recompile_status` | force a recompile and read its state |
| `editor.save_all` | save open scenes; before `scene.open`, play mode, a recompile and a build |
| `scene.open --path Assets/Scenes/X.unity` | open a scene (`--additive true` to add it) |
| `editor.playmode.start`, `editor.playmode.stop` | enter and leave play mode |
| `capture.game_view --save_path <path>` | a PNG of the Game view; the default `source=screen` includes overlay UI |
| `script.eval`, `script.eval_file` | arbitrary C# in the Editor: the text compiles as a statement body, so no `using` directives, fully qualified types, and `return` a value to get one back; `eval_file` caps its timeout at 30000 ms |

`unity command --project-path "<project>" --query <word>` lists the commands whose name or description
matches; `--detail full` adds their parameters.

## Timeouts and dialogs

- A command that returns "Timed out waiting" has usually finished anyway; the status call is the truth.
  The first call of a session can time out once and work on a plain retry.
- A run that never completes: read `editor.status`. `compiling` or `domainReloadInProgress` means wait. A
  status that stays `ready` with no result for far longer than the expected time means a dialog is up:
  report its title and stop. Never click a dialog; dismissing "Scene(s) Have Been Modified" discards work.
  `editor.save_all` before scene opens, play mode and recompiles prevents the common one.
- Never change an open scene or asset on disk under the Editor (a `git checkout` of a `.unity`, a branch
  switch): it raises a reload dialog. Switch the Editor to another scene first.
- Only one driver per Editor: subagents never run Unity commands, and a second session on the same project
  collides with yours.
