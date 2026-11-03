<#
PreToolUse hook -- keeps the review agent out of Unity asset files.

Why: a reviewer judges code. Asset, scene, prefab and meta files are serialized data, they are large
and keep growing, and in practice they are a large share of everything a reviewer reads: opened
directly, and carried in through a PR diff taken without a path filter.

Applies only to calls made by this plugin's `reviewer` agent. The main session and every other agent
are untouched. A review run by hand in the main session has no agent name on its calls, so there the
same rule lives in the code-review skill text.

What the reviewer may still do with assets: see their names in a file list, read a .meta file for
its guid, and run a search that answers only "which assets contain this text" (a renamed serialized
field, a script's guid).

A guard on the ordinary routes, not a sandbox. Blocks with exit code 2; stderr is fed back to the
agent as the reason, and every reason names the command to run instead.

Registered in hooks/hooks.json for PreToolUse on Read, Grep and Bash.
#>

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\skills\code-review\scripts\UnityAssetFiles.ps1')

$FilteredDiffScript = (Join-Path $PSScriptRoot '..\skills\code-review\scripts\review-diff.ps1') -replace '\\', '/'

function Get-ReviewerBlockReason($payload) {
  if (-not (Test-CallComesFromTheReviewer $payload)) { return $null }

  switch ([string]$payload.tool_name) {
    'Read' { return Get-ReadBlockReason ([string]$payload.tool_input.file_path) }
    'Grep' { return Get-GrepBlockReason $payload.tool_input }
    'Bash' { return Get-BashBlockReason ([string]$payload.tool_input.command) }
  }
  return $null
}

function Test-CallComesFromTheReviewer($payload) {
  # A plugin agent reports its name with the plugin in front ("unity-clean-architecture:reviewer").
  return ([string]$payload.agent_type) -match '^(unity-clean-architecture:)?reviewer$'
}

function Get-ReadBlockReason([string]$filePath) {
  if (Test-IsUnityAssetFile $filePath) { return (Get-AssetReadReason $filePath) }
  return $null
}

function Get-GrepBlockReason($grepInput) {
  $showsMatchingLines = ([string]$grepInput.output_mode) -eq 'content'
  $targetsAssets = (Test-IsUnityAssetFile ([string]$grepInput.path)) -or (Test-GlobSelectsAssets ([string]$grepInput.glob))

  if ($showsMatchingLines -and $targetsAssets) {
    return "BLOCKED: a reviewer does not read asset content. To learn which assets contain a text, run the same search with output_mode `"files_with_matches`"."
  }
  return $null
}

function Test-GlobSelectsAssets([string]$glob) {
  $extensions = $UnityAssetExtensions -join '|'
  return $glob -match "\.($extensions)$" -or $glob -match "[{,]($extensions)[},]"
}

function Get-BashBlockReason([string]$command) {
  foreach ($step in (Split-IntoCommandSteps $command)) {
    $reason = Get-StepBlockReason $step
    if ($reason) { return $reason }
  }
  return $null
}

function Split-IntoCommandSteps([string]$command) {
  # One step per simple command. A separator inside quotes belongs to the text, not to the shell:
  # grep "a\|b" is one step.
  $steps = @()
  $text = ''
  $openQuote = $null
  $readsFromAPipe = $false
  $nextReadsFromAPipe = $false

  for ($index = 0; $index -lt $command.Length; $index++) {
    $character = $command[$index]
    $nextTwo = if ($index + 1 -lt $command.Length) { $command.Substring($index, 2) } else { '' }

    if ($openQuote) {
      $text += $character
      $isEscapedCharacter = $openQuote -eq '"' -and $character -eq '\' -and $index + 1 -lt $command.Length
      if ($isEscapedCharacter) { $index++; $text += $command[$index] }
      elseif ($character -eq $openQuote) { $openQuote = $null }
      continue
    }
    if ($character -eq '"' -or $character -eq "'") { $openQuote = $character; $text += $character; continue }

    $endsTheStep = $true
    if ($nextTwo -eq '&&' -or $nextTwo -eq '||')    { $nextReadsFromAPipe = $false; $index++ }
    elseif ($character -eq '|')                     { $nextReadsFromAPipe = $true }
    elseif (';', "`n", "`r" -contains $character)   { $nextReadsFromAPipe = $false }
    else { $endsTheStep = $false; $text += $character }

    if ($endsTheStep) {
      if ($text.Trim()) { $steps += [pscustomobject]@{ Text = $text.Trim(); ReadsFromAPipe = $readsFromAPipe } }
      $text = ''
      $readsFromAPipe = $nextReadsFromAPipe
    }
  }
  if ($text.Trim()) { $steps += [pscustomobject]@{ Text = $text.Trim(); ReadsFromAPipe = $readsFromAPipe } }
  return $steps
}

function Get-StepBlockReason($commandStep) {
  if (Test-OnlyFiltersPipedText $commandStep) { return $null }

  $step = [string]$commandStep.Text
  $stepWithoutExcludedPaths = Remove-ExcludedPaths (Remove-GitDirectoryOption $step)

  if (Test-IsUnityAssetFile $stepWithoutExcludedPaths) {
    if (Test-OnlyListsOrCounts $stepWithoutExcludedPaths) { return $null }
    return (Get-AssetReadReason ([regex]::Match($stepWithoutExcludedPaths, "\S*$UnityAssetFilePattern").Value.Trim('"', "'")))
  }

  if (Test-PrintsAWholeChange $stepWithoutExcludedPaths) {
    if (Test-ChangeIsLimitedToCode $step $stepWithoutExcludedPaths) { return $null }
    return (Get-UnfilteredDiffReason)
  }
  return $null
}

function Test-OnlyFiltersPipedText($commandStep) {
  # "... --name-only | grep -v '\.asset'" filters what the step before it printed, and that step was
  # judged on its own. The asset name here is a text to search for, not a file being opened.
  return $commandStep.ReadsFromAPipe -and
         $commandStep.Text -match '^(grep|egrep|rg|sed|awk|head|tail|wc|sort|uniq|cut|tr|nl|cat|column)\b'
}

function Remove-GitDirectoryOption([string]$step) {
  # "git -C C:/repo show HEAD" must read as "git show HEAD": the drive letter's colon is not a rev:path.
  return $step -replace 'git\s+-C\s+("[^"]+"|''[^'']+''|\S+)', 'git'
}

function Remove-ExcludedPaths([string]$step) {
  # A path the command leaves OUT, such as ':(exclude)*.asset', is not a path it reads.
  return $step -replace '["'']?:(\(exclude[^)]*\)|!|\^)[^\s"'']*["'']?', ''
}

function Test-OnlyListsOrCounts([string]$step) {
  $printsALabel = $step -match '^(echo|printf)\b' -and $step -notmatch '\$\(|`'
  if ($printsALabel) { return $true }

  if ($step -match '--name-only|--name-status|--stat\b|--numstat|--shortstat|--summary') { return $true }

  $isSearch = $step -match '\b(grep|rg|findstr)\b'
  $searchPrintsNamesOrCounts = $step -cmatch '(^|\s)-[a-zA-Z]*[lLc][a-zA-Z]*(\s|$)' -or
                               $step -match '--files-with-matches|--files-without-match|--count\b'
  if ($isSearch) { return $searchPrintsNamesOrCounts }

  $printsFileContent = $step -match '\b(cat|sed|head|tail|awk|less|more|nl|tac|strings|xxd|od|python3?|node|perl|Get-Content)\b' -or
                       $step -match 'git\s+(show|cat-file|blame|diff|format-patch)\b' -or
                       $step -match 'git\s+log\b.*(\s-p\b|--patch)' -or
                       $step -match 'gh\s+pr\s+diff'
  if ($printsFileContent) { return $false }

  return $step -match '\b(ls|dir|find|wc|du|stat|test|echo|printf)\b|git\s+(ls-files|ls-tree|log|status)\b'
}

function Test-PrintsAWholeChange([string]$step) {
  return $step -match 'gh\s+pr\s+diff' -or
         $step -match 'git\s+(diff|show|format-patch)\b' -or
         $step -match 'git\s+log\b.*(\s-p\b|--patch)'
}

function Test-ChangeIsLimitedToCode([string]$step, [string]$stepWithoutExcludedPaths) {
  if ($stepWithoutExcludedPaths -match '--name-only|--name-status|--stat\b|--numstat|--shortstat|--summary') { return $true }
  if ($stepWithoutExcludedPaths -match 'gh\s+pr\s+diff') { return $false }
  if (Test-ShowsOneFileAtARevision $stepWithoutExcludedPaths) { return $true }

  $leavesAssetsOut = (Remove-GitDirectoryOption $step) -match ':(\(exclude[^)]*\)|!|\^)\S*\.asset'
  if ($leavesAssetsOut) { return $true }

  return (Test-EveryNamedPathIsAFile $stepWithoutExcludedPaths)
}

function Test-ShowsOneFileAtARevision([string]$step) {
  # "git show <revision>:<path>" prints that one file, and an asset path was already refused above.
  return $step -match 'git\s+show\b' -and $step -match '(^|\s)["'']?(?![A-Za-z]:[\\/])[^\s"'':]+:[^\s"'']+'
}

function Test-EveryNamedPathIsAFile([string]$step) {
  # After "--" come the paths. A folder, or ".", would bring every asset under it into the output.
  $separator = [regex]::Match($step, '\s--\s+(.+)$')
  if (-not $separator.Success) { return $false }

  $namedPaths = $separator.Groups[1].Value -split '\s+' | ForEach-Object { $_.Trim('"', "'") } | Where-Object { $_ }
  if (-not $namedPaths) { return $false }

  foreach ($path in $namedPaths) {
    $hasFileExtension = $path -match '\.[A-Za-z0-9]+$'
    if (-not $hasFileExtension) { return $false }
  }
  return $true
}

function Get-AssetReadReason([string]$assetPath) {
  return @"
BLOCKED: '$assetPath' is a Unity asset, and a reviewer does not read assets.

They are serialized data, not code, and nothing in one is yours to judge. What you may do:
  - see which assets a change touches: the FILES list printed by the command below;
  - learn which assets store a serialized field name:  grep -rl "<fieldName>" <folder> --include=*.asset
  - learn which assets reference a script: read the script's .meta for its guid, then  git grep -l <guid> -- Assets
A behaviour tree is reviewed from the description the caller handed you, never from its asset.
If your prompt came without one and the change is a tree, say so in the report's Scope line.

The change, without assets:
  powershell -ExecutionPolicy Bypass -File "$FilteredDiffScript" -Pr <number> -Repo "<repo path>"
"@
}

function Get-UnfilteredDiffReason {
  return @"
BLOCKED: this prints a whole change, asset files included. In a Unity PR that is often a third of the output.

Take the change without assets instead (file list first, then the diff of code, assembly definitions and docs):
  powershell -ExecutionPolicy Bypass -File "$FilteredDiffScript" -Pr <number> -Repo "<repo path>"
  powershell -ExecutionPolicy Bypass -File "$FilteredDiffScript" -Base <ref> -Head <ref> -Repo "<repo path>"

Still allowed as they are: --name-only / --stat forms, "git show <revision>:<path>" for one code file,
and a diff whose paths after "--" are all files (for example  -- '*.cs' '*.asmdef').
"@
}

$isRunAsAHook = $MyInvocation.InvocationName -ne '.'
if ($isRunAsAHook) {
  # Never block on our own bug: an unreadable payload or a failure in here lets the call through.
  try   { $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { exit 0 }
  try   { $reason = Get-ReviewerBlockReason $payload }               catch { exit 0 }

  if ($reason) {
    [Console]::Error.WriteLine($reason)
    exit 2
  }
  exit 0
}
