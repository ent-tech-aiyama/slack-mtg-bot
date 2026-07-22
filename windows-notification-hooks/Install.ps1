# Install.ps1
# ------------------------------------------------------------------------------
# Claude Code 通知フック（Windows 用）を自動セットアップするスクリプト。
#
# やること:
#   1. claude-notify.ps1 を  %USERPROFILE%\.claude\hooks\  にコピー
#   2. %USERPROFILE%\.claude\settings.json に Notification / Stop フックを追記
#      （既存の設定・他のフックは壊さずに保持。上書き前にバックアップを作成）
#   3. （任意）BurntToast モジュールを導入
#   4. テスト実行（画面通知 + ntfy 送信を確認）
#
# 使い方（PowerShell で、このスクリプトがあるフォルダから）:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
#
# オプション:
#   -InstallBurntToast   BurntToast を CurrentUser にインストールする
#   -SkipTest            最後のテスト実行をスキップする
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [switch]$InstallBurntToast,
    [switch]$SkipTest
)

$ErrorActionPreference = 'Stop'

function ConvertTo-HashtableRecursive {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-HashtableRecursive $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableRecursive $p.Value }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-HashtableRecursive $_ })
    }
    return $InputObject
}

# --- パス -----------------------------------------------------------------------
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcScript    = Join-Path $scriptDir 'claude-notify.ps1'
$claudeDir    = Join-Path $env:USERPROFILE '.claude'
$hooksDir     = Join-Path $claudeDir 'hooks'
$destScript   = Join-Path $hooksDir 'claude-notify.ps1'
$settingsPath = Join-Path $claudeDir 'settings.json'

if (-not (Test-Path -LiteralPath $srcScript)) {
    throw "claude-notify.ps1 が見つかりません: $srcScript"
}

# --- 1) スクリプトをコピー ------------------------------------------------------
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
Copy-Item -LiteralPath $srcScript -Destination $destScript -Force
Write-Host "[OK] フックスクリプトを配置: $destScript"

# --- 2) settings.json をマージ --------------------------------------------------
$settings = [ordered]@{}
if (Test-Path -LiteralPath $settingsPath) {
    $backup = "$settingsPath.bak"
    Copy-Item -LiteralPath $settingsPath -Destination $backup -Force
    Write-Host "[OK] 既存 settings.json をバックアップ: $backup"
    try {
        $existing = Get-Content -Raw -LiteralPath $settingsPath -Encoding UTF8 | ConvertFrom-Json
        $settings = ConvertTo-HashtableRecursive $existing
        if ($null -eq $settings) { $settings = [ordered]@{} }
    } catch {
        throw "既存の settings.json が壊れているため中断しました（$settingsPath）。手動で確認してください。"
    }
}

$hookCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$destScript`""
$makeEntry = { @{ hooks = @( @{ type = 'command'; command = $hookCmd; timeout = 15 } ) } }

if (-not $settings.Contains('hooks') -or $null -eq $settings['hooks']) {
    $settings['hooks'] = [ordered]@{}
} else {
    $settings['hooks'] = ConvertTo-HashtableRecursive $settings['hooks']
}
$settings['hooks']['Notification'] = @(& $makeEntry)
$settings['hooks']['Stop']         = @(& $makeEntry)

$json = $settings | ConvertTo-Json -Depth 20
# ConvertTo-Json のエスケープ（< 等）を読みやすさのため戻す（任意）
Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
Write-Host "[OK] settings.json に Notification / Stop フックを設定: $settingsPath"

# --- 3) BurntToast（任意）------------------------------------------------------
if ($InstallBurntToast) {
    if (Get-Module -ListAvailable -Name BurntToast) {
        Write-Host "[OK] BurntToast は既にインストール済み"
    } else {
        try {
            Install-Module -Name BurntToast -Scope CurrentUser -Force -AllowClobber
            Write-Host "[OK] BurntToast をインストールしました"
        } catch {
            Write-Warning "BurntToast のインストールに失敗（フォールバックのトーストで動作します）: $_"
        }
    }
} else {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Write-Host "[INFO] BurntToast は未導入です。ネイティブトーストで動作します。"
        Write-Host "       きれいなトーストにしたい場合: Install-Module -Name BurntToast -Scope CurrentUser"
    }
}

# --- 4) テスト ------------------------------------------------------------------
if (-not $SkipTest) {
    Write-Host ""
    Write-Host "テストを実行します（画面通知 + スマホ ntfy に届くはず）..."
    $testJson = @{ hook_event_name = 'Notification'; message = 'テスト通知です（セットアップ確認）' } | ConvertTo-Json -Compress
    $testJson | & powershell -NoProfile -ExecutionPolicy Bypass -File $destScript
    Write-Host "[OK] テスト送信しました。画面右下の通知と、スマホの ntfy アプリを確認してください。"
}

Write-Host ""
Write-Host "完了しました。反映されない場合は Claude Code で /hooks を開くか、Claude Code を再起動してください。"
