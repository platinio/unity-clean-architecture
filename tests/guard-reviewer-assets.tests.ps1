<#
Tests for hooks/guard-reviewer-assets.ps1. No test framework needed:

  powershell -ExecutionPolicy Bypass -File tests/guard-reviewer-assets.tests.ps1

Each case is a tool call the review agent could make and whether the guard must let it through.
The commands are the shapes real reviewers used, taken from PR review transcripts.
Exit code 0 when every case holds, 1 otherwise.

  -ReplayFile <path>   also replay recorded calls (one JSON object per line: tool_name, tool_input,
                       expect "allow" | "block") and report every mismatch. Used before a release to
                       check the guard against real transcripts; the recordings are not in this repo.
#>
param([string]$ReplayFile = '')

. (Join-Path $PSScriptRoot '..\hooks\guard-reviewer-assets.ps1')

$reviewer = 'unity-clean-architecture:reviewer'
$failures = 0

function Assert-Call([string]$expected, [string]$agentType, [string]$toolName, $toolInput, [string]$why) {
  $payload = [pscustomobject]@{ agent_type = $agentType; tool_name = $toolName; tool_input = [pscustomobject]$toolInput }
  $actual = if (Get-ReviewerBlockReason $payload) { 'block' } else { 'allow' }
  if ($actual -ne $expected) {
    $script:failures++
    $shown = if ($toolInput.command) { $toolInput.command } else { ($toolInput | ConvertTo-Json -Compress) }
    Write-Output "FAIL  expected $expected, got $actual  [$why]`n      $toolName  $shown"
  }
}

function Assert-Bash([string]$expected, [string]$command, [string]$why) {
  Assert-Call $expected $reviewer 'Bash' @{ command = $command } $why
}

# ---- who the guard applies to ---------------------------------------------------------------------
Assert-Call 'block' $reviewer                      'Read' @{ file_path = 'C:/p/Assets/Trees/ThugRoot.asset' } 'reviewer reads an asset'
Assert-Call 'block' 'reviewer'                     'Read' @{ file_path = 'C:/p/Assets/Trees/ThugRoot.asset' } 'agent name without the plugin in front'
Assert-Call 'allow' ''                             'Read' @{ file_path = 'C:/p/Assets/Trees/ThugRoot.asset' } 'main session is untouched'
Assert-Call 'allow' 'unity-clean-architecture:explorer' 'Read' @{ file_path = 'C:/p/Assets/Scenes/CombatArena.unity' } 'another agent is untouched'
Assert-Call 'allow' 'general-purpose'              'Bash' @{ command = 'gh pr diff 12' } 'another agent may take a whole diff'

# ---- Read -----------------------------------------------------------------------------------------
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:\p\Assets\ArkhamCombat\Runtime\Combat\ActionRunner.cs' } 'code'
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:/p/Assets/ArkhamCombat/Runtime/ArkhamCombat.Combat.asmdef' } 'assembly definitions stay readable'
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:/p/Docs/design/02-enemy-behavior-trees.md' } 'the spec'
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:/p/Assets/Editor/AssetsPostprocessor.cs' } 'the word asset in a code file name'
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:/p/Assets/Runtime/Combat.Meta.cs' } 'an asset word in the middle of a code file name'
Assert-Call 'block' $reviewer 'Read' @{ file_path = 'C:\p\Assets\Scenes\CombatArena.unity' } 'scene'
Assert-Call 'block' $reviewer 'Read' @{ file_path = 'C:/p/Assets/Prefabs/Thug.prefab' } 'prefab'
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:/p/Assets/ArkhamCombat/Runtime/ActionRunner.cs.meta' } 'a meta file holds the guid'
Assert-Call 'allow' $reviewer 'Read' @{ file_path = 'C:/p/Assets/Trees/ThugRoot.asset.meta' } 'the meta of an asset is still a meta'
Assert-Call 'block' $reviewer 'Read' @{ file_path = 'C:/p/Assets/Art/Thug.MAT' } 'extension in capitals'

# ---- Grep -----------------------------------------------------------------------------------------
Assert-Call 'allow' $reviewer 'Grep' @{ pattern = 'comboWindow'; path = 'C:/p/Assets'; glob = '*.asset'; output_mode = 'files_with_matches' } 'which assets store a field'
Assert-Call 'allow' $reviewer 'Grep' @{ pattern = 'comboWindow'; path = 'C:/p/Assets'; glob = '*.asset' } 'default mode lists files'
Assert-Call 'block' $reviewer 'Grep' @{ pattern = 'comboWindow'; path = 'C:/p/Assets'; glob = '*.asset'; output_mode = 'content' } 'asset content through search'
Assert-Call 'block' $reviewer 'Grep' @{ pattern = 'guid'; path = 'C:/p/Assets'; glob = '**/*.{prefab,unity}'; output_mode = 'content' } 'asset content through a brace glob'
Assert-Call 'block' $reviewer 'Grep' @{ pattern = 'guid'; path = 'C:/p/Assets/Scenes/CombatArena.unity'; output_mode = 'content' } 'asset content by path'
Assert-Call 'allow' $reviewer 'Grep' @{ pattern = 'ActionRunner'; path = 'C:/p/Assets'; glob = '*.cs'; output_mode = 'content' } 'code content'

# ---- Bash: taking the change ----------------------------------------------------------------------
Assert-Bash 'block' 'gh pr diff 43' 'a whole PR diff'
Assert-Bash 'block' 'cd "C:/p" && gh pr diff 43 > /tmp/pr43.diff; wc -c /tmp/pr43.diff' 'a whole PR diff inside a longer line'
Assert-Bash 'allow' 'gh pr diff 43 --name-only' 'file names only'
Assert-Bash 'allow' 'gh pr view 43 --json title,body,files' 'the description'
Assert-Bash 'block' 'git -C "C:/p" diff origin/main...FETCH_HEAD' 'a whole range diff'
Assert-Bash 'block' 'git -C C:/Users/Admin/p show FETCH_HEAD' 'a whole commit; the drive letter is not a rev:path'
Assert-Bash 'block' 'git diff main...HEAD -- Assets/ArkhamCombat' 'a folder brings its assets along'
Assert-Bash 'block' 'git diff main...HEAD -- .' 'the whole tree'
Assert-Bash 'block' 'git log -p -3' 'patches through log'
Assert-Bash 'allow' 'git -C "C:/p" diff --stat origin/main...FETCH_HEAD' 'stat'
Assert-Bash 'allow' 'git diff --name-status main...HEAD' 'name-status'
Assert-Bash 'allow' "git -C `"C:/p`" diff origin/main...FETCH_HEAD -- '*.cs' '*.asmdef'" 'paths are all files'
Assert-Bash 'block' 'git diff main...HEAD | grep -n "Ignore"' 'tamper markers searched in a whole diff'
Assert-Bash 'allow' "git diff main...HEAD -- '*.cs' | grep -n `"\[Ignore\]`"" 'tamper markers searched in the code diff'
Assert-Bash 'allow' "git diff main...HEAD -- . ':(exclude)*.asset' ':(exclude)*.unity' ':(exclude)*.prefab' ':(exclude)*.meta'" 'assets left out by hand'
Assert-Bash 'allow' 'git -C "C:/p" show FETCH_HEAD:Assets/ArkhamCombat/Runtime/Combat/ActionRunner.cs' 'one code file at a revision'
Assert-Bash 'allow' 'git -C "C:/Users/Admin/p" show 4f2a9c1:Assets/ArkhamCombat/Runtime/ArkhamCombat.Combat.asmdef' 'one asmdef at a revision'
Assert-Bash 'allow' 'git -C "C:/p" log --oneline -15' 'history without patches'
Assert-Bash 'allow' 'git -C "C:/p" fetch origin feature/enemy-trees' 'fetch'
Assert-Bash 'allow' 'powershell -ExecutionPolicy Bypass -File "C:/plugins/unity-clean-architecture/skills/code-review/scripts/review-diff.ps1" -Pr 43 -Repo "C:/p"' 'the filtered diff script'

# ---- Bash: asset files ----------------------------------------------------------------------------
Assert-Bash 'block' 'git -C "C:/p" show FETCH_HEAD:Assets/ArkhamCombat/Trees/Roots/ThugRoot.asset' 'one asset at a revision'
Assert-Bash 'block' 'cat "C:/p/Assets/ArkhamCombat/Config/EnemyArchetypes.asset"' 'cat'
Assert-Bash 'block' 'cd "C:/p" && sed -n "1,200p" Assets/Scenes/CombatArena.unity' 'sed'
Assert-Bash 'block' 'head -100 Assets/Prefabs/Thug.prefab' 'head'
Assert-Bash 'block' 'for f in Assets/Trees/*.asset; do echo "== $f"; cat "$f"; done' 'a loop that prints every asset'
Assert-Bash 'block' 'git -C "C:/p" diff origin/main...FETCH_HEAD -- Assets/Trees/ThugRoot.asset' 'a diff limited to an asset'
Assert-Bash 'block' 'grep -n "comboWindow" Assets/Config/CombatConfig.asset' 'search that prints asset lines'
Assert-Bash 'allow' 'cat Assets/Runtime/ActionRunner.cs.meta' 'meta through cat'
Assert-Bash 'block' 'git show FETCH_HEAD:Assets/CombatArena.unity | grep -n "m_Name"' 'lines picked out of a scene are still the scene'
Assert-Bash 'block' "git grep -n -i `"encounter`" origin/feature/x -- '*.unity' '*.prefab'" 'git grep that prints asset lines'
Assert-Bash 'block' 'for f in Trees/Roots/ThugRoot.asset Trees/SubTrees/Idle.asset; do echo "== $f"; git show HEAD:Assets/$f; done' 'a loop over named assets'
Assert-Bash 'allow' 'echo "=== Dummy.asset guid"; DG=$(git show FETCH_HEAD:Assets/HitProfiles/Dummy.asset.meta | grep guid | awk ''{print $2}''); git grep -l "$DG" FETCH_HEAD -- Assets' 'which assets reference this one, through its guid'
Assert-Bash 'allow' 'grep -rl "comboWindow\|hitWindow" Assets --include=*.asset' 'a separator inside quotes does not split the command'
Assert-Bash 'allow' "gh pr diff 43 --name-only | grep -v '\.asset' | grep -v `"\.meta`"" 'an asset name used as a filter on a file list'
Assert-Bash 'allow' 'grep -rl "comboWindow" Assets --include=*.asset' 'which assets store a field'
Assert-Bash 'allow' 'grep -rc "m_Script" Assets/Trees --include=*.asset' 'counts only'
Assert-Bash 'allow' 'git -C "C:/p" grep -l "comboWindow" -- "*.asset" "*.prefab"' 'git grep that lists files'
Assert-Bash 'allow' 'ls -la Assets/ArkhamCombat/Trees/Roots/' 'listing a folder of assets'
Assert-Bash 'allow' 'find Assets -name "*.asset" -newer Assets/x.cs' 'finding assets by name'
Assert-Bash 'allow' 'git -C "C:/p" ls-files "*.unity"' 'tracked scenes by name'
Assert-Bash 'allow' 'git -C "C:/p" log --oneline -- Assets/Trees/ThugRoot.asset' 'which commits touched an asset'
Assert-Bash 'allow' 'wc -c Assets/Trees/ThugRoot.asset' 'size of an asset'
Assert-Bash 'allow' 'echo "--- Dummy.asset (head)"' 'a label that names an asset and happens to say head'
Assert-Bash 'block' 'echo "$(cat Assets/Config/CombatConfig.asset)"' 'a label that prints an asset'

# ---- Bash: code ------------------------------------------------------------------------------------
Assert-Bash 'allow' 'cat "C:/p/Assets/ArkhamCombat/Runtime/Combat/Runner/ActionRunner.cs"' 'code through cat'
Assert-Bash 'allow' 'cd "C:/p" && for f in Runtime/Combat/ActionRunner.cs Runtime/Combat/ComboMeter.cs; do echo "=================== $f"; cat "$f"; done' 'several code files'
Assert-Bash 'allow' 'grep -rn "IActionTargetPicker" Assets --include=*.cs' 'code search'
Assert-Bash 'allow' 'grep -rn "AssetDatabase" Assets/Editor --include=*.cs | head -20' 'the word asset in a code search'
Assert-Bash 'allow' 'cat Assets/ArkhamCombat/Tests/EditMode/ArkhamCombat.Tests.asmdef' 'asmdef through cat'
Assert-Bash 'allow' 'git -C "C:/p" submodule status' 'submodules'

if ($ReplayFile) {
  $replayed = 0
  foreach ($line in [System.IO.File]::ReadLines($ReplayFile)) {
    if (-not $line.Trim()) { continue }
    $recorded = $line | ConvertFrom-Json
    $toolInput = @{}
    foreach ($property in $recorded.tool_input.PSObject.Properties) { $toolInput[$property.Name] = $property.Value }
    Assert-Call $recorded.expect $reviewer $recorded.tool_name $toolInput "replay $($recorded.source)"
    $replayed++
  }
  Write-Output "replayed $replayed recorded calls"
}

if ($failures) { Write-Output "$failures FAILED"; exit 1 }
Write-Output 'all cases hold'
exit 0
