<#
The one list of file types that count as Unity assets for a code review: serialized data the Editor
writes, large, growing, and not something a reader of code can judge. The reviewer guard blocks them
and review-diff.ps1 leaves them out of the diff, so both dot-source this file.

Assembly definitions are deliberately absent: they are small and the check that editor code is not
reachable from runtime depends on reading them.

A .meta file is ten lines and holds the guid that answers "which assets reference this script", so a
reviewer may read one. A diff still leaves them out: one arrives with every new file and says nothing.
#>

$UnityAssetExtensions = @(
  'asset', 'unity', 'prefab',
  'mat', 'controller', 'overrideController', 'anim', 'playable',
  'physicMaterial', 'physicsMaterial2D', 'lighting', 'mixer', 'preset',
  'spriteatlas', 'renderTexture', 'flare', 'guiskin', 'fontsettings', 'terrainlayer',
  'shadergraph', 'shadersubgraph', 'vfx'
)

# Matches an asset extension only where a file name ends: before a space, a quote, a closing
# bracket, a colon, or the end of the text. "Foo.asset" matches; "Foo.assets" and "Foo.Meta.cs" do not.
$UnityAssetFilePattern = '\.(' + ($UnityAssetExtensions -join '|') + ')(?=$|[\s"''`)\]:,;])'

$ExtensionsLeftOutOfAReviewDiff = $UnityAssetExtensions + 'meta'

function Test-IsUnityAssetFile([string]$path) {
  return $path -match $UnityAssetFilePattern
}
