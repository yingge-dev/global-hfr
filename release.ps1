param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo

if ($Version -notmatch '^v\d+\.\d+\.\d+$') {
  throw "Version must look like v1.2.3"
}

if (Test-Path ".git\refs\tags\$Version") {
  throw "tag $Version already exists"
}

$dirty = git status --porcelain
if ($dirty) {
  throw "Working tree has uncommitted changes. Commit or stash them first."
}

$prop = Join-Path $repo 'module\module.prop'
$text = [IO.File]::ReadAllText($prop, [Text.Encoding]::UTF8)
$m = [regex]::Match($text, '(?m)^versionCode=(\d+)\s*$')
if (-not $m.Success) {
  throw "versionCode not found in module.prop"
}
$newCode = [int]$m.Groups[1].Value + 1

$text = [regex]::Replace($text, '(?m)^version=.*$', "version=$Version")
$text = [regex]::Replace($text, '(?m)^versionCode=.*$', "versionCode=$newCode")
[IO.File]::WriteAllText($prop, $text, (New-Object Text.UTF8Encoding($false)))

if (-not (git config user.email)) {
  git config user.email 'yingge-dev@users.noreply.github.com'
  git config user.name 'Yingge'
}

git add module/module.prop
git commit -m "release: $Version"
git push
git tag $Version
git push origin $Version

Write-Host ""
Write-Host "Pushed $Version (versionCode=$newCode)."
Write-Host "GitHub Actions will build the zip, create the release, and update update.json and the Pages download."
Write-Host "https://github.com/yingge-dev/global-hfr/releases/tag/$Version"
