<#
Prints a change the way a code reviewer should receive it: every changed file by name, then the diff
with Unity asset files left out. One call, and nothing in it is serialized Editor data.

  powershell -ExecutionPolicy Bypass -File <plugin-root>/skills/code-review/scripts/review-diff.ps1 -Pr 21 -Repo "C:\path\to\repo"
  powershell -ExecutionPolicy Bypass -File <plugin-root>/skills/code-review/scripts/review-diff.ps1 -Base origin/main -Head HEAD -Repo "C:\path\to\repo"

  -Pr     a pull request number in the repository at -Repo. Its head is fetched (never checked out, so
          an open Unity Editor is not disturbed) and compared with its base branch.
  -Base / -Head   two git revisions, for a branch that has no PR yet.
  -Repo   the checkout to run in: the main checkout, or a submodule's folder when the PR lives on the
          submodule's repository. Defaults to the current directory.

Output:
  FILES   one line per changed file with its status; asset files are listed and marked, never shown
  HEAD    the head revision, and the command that prints one changed code file whole
  DIFF    the change in code, assembly definitions and docs. Printed when it is short. A long one is
          saved to a file and the output names the file and the line ranges to read, because output
          past about 30,000 characters is cut off and has to be fetched again, which costs a turn.

Exit codes: 0 printed | 1 bad arguments | 2 git or gh failed (the message says which call)
#>
param(
  [int]$Pr = 0,
  [string]$Base = '',
  [string]$Head = '',
  [string]$Repo = ''
)

$ErrorActionPreference = 'Stop'

# git prints UTF-8. Without this, every character outside ASCII in a diff arrives garbled.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'UnityAssetFiles.ps1')

$LongestDiffPrintedWhole = 18000    # characters, leaving room for the file list under the output limit
$LinesPerRead = 1200

function Stop-WithMessage([string]$message, [int]$exitCode) {
  [Console]::Error.WriteLine($message)
  exit $exitCode
}

function Invoke-Git([string[]]$gitArguments) {
  $output = & git -C $repositoryRoot @gitArguments 2>&1
  if ($LASTEXITCODE -ne 0) { Stop-WithMessage "git $($gitArguments -join ' ') failed:`n$($output -join "`n")" 2 }
  return $output
}

function Get-RepositoryRoot([string]$startFolder) {
  $root = & git -C $startFolder rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $root) { Stop-WithMessage "'$startFolder' is not inside a git repository." 1 }
  return $root
}

function Get-PullRequestRevisions([int]$number) {
  Push-Location $repositoryRoot
  try     { $json = & gh pr view $number --json baseRefName,headRefOid 2>&1 }
  finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { Stop-WithMessage "gh pr view $number failed:`n$($json -join "`n")" 2 }

  $pullRequest = $json | ConvertFrom-Json
  Invoke-Git @('fetch', '--quiet', 'origin', $pullRequest.baseRefName) | Out-Null
  Invoke-Git @('fetch', '--quiet', 'origin', "pull/$number/head") | Out-Null

  return @{ Base = "origin/$($pullRequest.baseRefName)"; Head = $pullRequest.headRefOid }
}

function Write-ChangedFiles([string]$changeRange) {
  $changedFiles = @(Invoke-Git @('diff', '--name-status', $changeRange))
  $metaFiles    = @($changedFiles | Where-Object { $_ -match '\.meta$' })
  $assetFiles   = @($changedFiles | Where-Object { Test-IsUnityAssetFile $_ })

  Write-Output "FILES  $($changedFiles.Count) changed; $($assetFiles.Count) asset files and $($metaFiles.Count) meta files are listed by name and left out of the diff"
  foreach ($changedFile in $changedFiles) {
    $mark = if (Test-IsUnityAssetFile $changedFile) { '   [asset: not shown]' } else { '' }
    Write-Output "  $changedFile$mark"
  }
}

function Write-DiffWithoutAssets([string]$changeRange, [string]$headRevision) {
  $pathsLeftOut = $ExtensionsLeftOutOfAReviewDiff | ForEach-Object { ":(exclude)*.$_" }
  $diffLines = @(Invoke-Git (@('diff', $changeRange, '--', '.') + $pathsLeftOut) | ForEach-Object { [string]$_ })
  $diffLength = ($diffLines | Measure-Object -Property Length -Sum).Sum + $diffLines.Count

  if ($diffLength -le $LongestDiffPrintedWhole) {
    Write-Output 'DIFF  code, assembly definitions and docs'
    Write-Output $diffLines
    return
  }

  $savedDiff = Save-Diff $diffLines $headRevision
  Write-Output "DIFF  code, assembly definitions and docs: $($diffLines.Count) lines, saved to a file because it is too long to print whole"
  Write-Output "  $savedDiff"
  Write-Output '  Read all of it with the Read tool, every range in ONE message:'
  for ($firstLine = 1; $firstLine -le $diffLines.Count; $firstLine += $LinesPerRead) {
    Write-Output "    offset $firstLine, limit $LinesPerRead"
  }
}

function Save-Diff([string[]]$diffLines, [string]$headRevision) {
  $folder = Join-Path ([System.IO.Path]::GetTempPath()) 'claude-review-diff'
  New-Item -ItemType Directory -Force -Path $folder | Out-Null

  $repositoryName = Split-Path $repositoryRoot -Leaf
  $file = Join-Path $folder "$repositoryName-$($headRevision.Substring(0, 10)).diff"
  [System.IO.File]::WriteAllLines($file, $diffLines, (New-Object System.Text.UTF8Encoding $false))
  return $file -replace '\\', '/'
}

if (-not $Repo) { $Repo = (Get-Location).Path }
$repositoryRoot = Get-RepositoryRoot $Repo

$isPullRequest = $Pr -gt 0
$isRevisionPair = $Base -and $Head
if (-not $isPullRequest -and -not $isRevisionPair) {
  Stop-WithMessage 'Give either -Pr <number>, or both -Base <ref> and -Head <ref>.' 1
}

if ($isPullRequest) { $revisions = Get-PullRequestRevisions $Pr }
else                { $revisions = @{ Base = $Base; Head = (Invoke-Git @('rev-parse', $Head)) } }

$changeRange = "$($revisions.Base)...$($revisions.Head)"

Write-ChangedFiles $changeRange
Write-Output ''
Write-Output "HEAD  $($revisions.Head)"
Write-Output "  read one changed code file whole:  git -C `"$repositoryRoot`" show $($revisions.Head):<path>"
Write-Output ''
Write-DiffWithoutAssets $changeRange ([string]$revisions.Head)
