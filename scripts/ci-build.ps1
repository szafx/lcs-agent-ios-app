# 一条命令：建仓库 → 推代码 → 触发 Actions → 等结果 → 拉 IPA
#
# 前置：gh 已登录（gh auth login）
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\ci-build.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\ci-build.ps1 -RepoName lcs-agent-ios -Private
param(
    [string]$RepoName = "lcs-agent-ios",
    [switch]$Private
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail($msg) { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[√] $msg" -ForegroundColor Green }
function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

Step "检查 gh"
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "没装 gh。先执行: winget install --id GitHub.cli -e"
}
gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "gh 未登录。先执行: gh auth login   （选 GitHub.com → HTTPS → 浏览器登录）"
}
$user = (gh api user --jq .login)
Ok "已登录：$user"

Step "初始化 git 仓库"
if (-not (Test-Path ".git")) {
    git init -b main | Out-Null
    Ok "git 仓库已建"
} else {
    Ok "已有 git 仓库"
}

git add -A
$changes = git status --porcelain
if ($changes) {
    git commit -m "build: LCSAgent iOS app" | Out-Null
    Ok "已提交变更"
} else {
    Ok "没有新变更"
}

Step "准备远端仓库 $RepoName"
$full = "$user/$RepoName"
gh repo view $full *> $null
if ($LASTEXITCODE -ne 0) {
    $vis = if ($Private) { "--private" } else { "--public" }
    gh repo create $RepoName $vis --source=. --remote=origin --push
    Ok "仓库已创建并推送：https://github.com/$full"
} else {
    git remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) { git remote add origin "https://github.com/$full.git" }
    git push -u origin main
    Ok "已推送到 https://github.com/$full"
}

Step "触发构建"
gh workflow run build-ipa.yml --repo $full
Start-Sleep -Seconds 6
$runId = gh run list --repo $full --workflow build-ipa.yml --limit 1 --json databaseId --jq ".[0].databaseId"
Ok "run id = $runId"

Step "等待构建结束（首次约 3-5 分钟）"
gh run watch $runId --repo $full --exit-status
if ($LASTEXITCODE -ne 0) {
    Write-Host "[x] 构建失败，下面是失败日志：" -ForegroundColor Red
    gh run view $runId --repo $full --log-failed
    exit 1
}
Ok "构建成功"

Step "下载产物"
New-Item -ItemType Directory -Force -Path "$root\dist" | Out-Null
gh run download $runId --repo $full -D "$root\dist"
Get-ChildItem "$root\dist" -Recurse -Filter *.ipa | ForEach-Object {
    Ok "IPA: $($_.FullName)  ($([math]::Round($_.Length/1MB,2)) MB)"
}

Write-Host ""
Ok "完成。把 .ipa 拖进 TrollStore / Sideloadly 即可安装。"
