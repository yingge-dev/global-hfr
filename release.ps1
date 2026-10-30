param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo

if ($Version -notmatch '^v\d+\.\d+\.\d+$') {
  throw "Version 必须形如 v1.2.3"
}

if (Test-Path ".git\refs\tags\$Version") {
  throw "tag $Version 已存在"
}

$dirty = git status --porcelain
if ($dirty) {
  throw "工作区还有未提交的改动，请先提交或撤销后再发版"
}

$prop = Join-Path $repo 'module\module.prop'
$text = [IO.File]::ReadAllText($prop, [Text.Encoding]::UTF8)
$m = [regex]::Match($text, '(?m)^versionCode=(\d+)\s*$')
if (-not $m.Success) {
  throw "module.prop 里找不到 versionCode"
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
Write-Host "已推送 $Version（versionCode=$newCode）。"
Write-Host "GitHub Actions 会自动打包、发 Release、更新 update.json 和 Pages 下载包。"
Write-Host "https://github.com/yingge-dev/global-hfr/releases/tag/$Version"
