# claude-notify.ps1
# ------------------------------------------------------------------------------
# Claude Code 通知フック（Windows 用）
#
# Notification フック（確認・許可待ち）と Stop フック（返答が終わって入力待ち）の
# 両方から呼ばれる 1 本のスクリプト。動作は 2 つ:
#   1. Windows のトースト通知 + 通知音を出す
#      （BurntToast があれば使用、無ければ WinRT ネイティブトーストにフォールバック）
#   2. ntfy へ送信（スマホ通知）
#
# Stop フックのときは、固定文ではなく「Claude の最後の返答」から通知文を作る:
#   - フックが受け取る JSON の transcript_path（会話記録 JSONL）を読み、
#     最後の assistant メッセージのテキストを取り出す
#   - そのうち 「👉」で始まる行があればそれを優先
#   - なければ本文の先頭 100 文字を使う
#
# フックの種類は、標準入力の JSON の hook_event_name で判定する。
# （Claude Code はフック実行時に stdin へ JSON を渡す）
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'SilentlyContinue'

# --- 設定 -----------------------------------------------------------------------
$NtfyTopic = 'claude-aiyama-91dfd2c474b1'   # Mac と共通のトピック（合言葉。他人に教えない）
$NtfyUrl   = "https://ntfy.sh/$NtfyTopic"
$MaxLen    = 100                             # 通知本文の最大文字数
$ArrowEmoji = [char]::ConvertFromUtf32(0x1F449)  # 👉
# ------------------------------------------------------------------------------

# --- 標準入力からフック JSON を読む ---------------------------------------------
$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch {}
$data = $null
if ($raw) { try { $data = $raw | ConvertFrom-Json } catch {} }

$eventName = $null
if ($data) { $eventName = $data.hook_event_name }

# --- transcript から最後の assistant テキストを取り出す -------------------------
function Get-LastAssistantText {
    param([string]$TranscriptPath)
    if (-not $TranscriptPath) { return $null }
    if (-not (Test-Path -LiteralPath $TranscriptPath)) { return $null }

    $lastText = $null
    foreach ($line in Get-Content -LiteralPath $TranscriptPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $obj = $null
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        if ($obj.type -ne 'assistant') { continue }

        $content = $obj.message.content
        if (-not $content) { continue }

        # content は文字列の場合と、ブロック配列の場合がある
        if ($content -is [string]) {
            if ($content.Trim()) { $lastText = $content }
            continue
        }
        $parts = @()
        foreach ($block in $content) {
            if ($block.type -eq 'text' -and $block.text) { $parts += [string]$block.text }
        }
        if ($parts.Count -gt 0) { $lastText = ($parts -join "`n") }
    }
    return $lastText
}

# --- Stop フック用: 最後の返答から通知本文を作る --------------------------------
function Get-StopBody {
    param($Data)
    $text = Get-LastAssistantText -TranscriptPath $Data.transcript_path
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '返答が終わりました。入力待ちです'
    }

    # 「👉」で始まる行があれば優先
    foreach ($ln in ($text -split "`r?`n")) {
        $t = $ln.Trim()
        if ($t.StartsWith($ArrowEmoji)) {
            return (Limit-Text $t)
        }
    }

    # 無ければ本文の先頭 $MaxLen 文字
    $flat = ($text -replace '\s+', ' ').Trim()
    return (Limit-Text $flat)
}

function Limit-Text {
    param([string]$Text)
    if (-not $Text) { return $Text }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen) + '…'
}

# --- Windows トースト通知（+ 音）------------------------------------------------
function Show-Toast {
    param([string]$Title, [string]$Body)

    $shown = $false

    # 1) BurntToast があればそれを使う
    if (Get-Module -ListAvailable -Name BurntToast) {
        try {
            Import-Module BurntToast -ErrorAction Stop
            New-BurntToastNotification -Text $Title, $Body -ErrorAction Stop
            $shown = $true
        } catch { $shown = $false }
    }

    # 2) フォールバック: WinRT ネイティブトースト（PowerShell 5.1 で動く）
    if (-not $shown) {
        try {
            $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

            $xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$([System.Security.SecurityElement]::Escape($Title))</text>
      <text>$([System.Security.SecurityElement]::Escape($Body))</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
"@
            $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
            $doc.LoadXml($xml)
            $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
            $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
            $shown = $true
        } catch { $shown = $false }
    }

    # 3) 最後の手段: メッセージ（msg.exe）
    if (-not $shown) {
        try { & msg.exe * "$Title`n$Body" } catch {}
    }

    # 通知音（トーストに音が付かない場合の保険）
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
}

# --- ntfy へ送信（スマホ）-------------------------------------------------------
function Send-Ntfy {
    param([string]$Message)
    try {
        # 日本語・絵文字を確実に送るため UTF-8 バイト列で送信
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        Invoke-RestMethod -Method Post -Uri $NtfyUrl -Body $bytes `
            -ContentType 'text/plain; charset=utf-8' | Out-Null
    } catch {}
}

# --- メイン ---------------------------------------------------------------------
$title = 'Claude Code'

switch ($eventName) {
    'Stop' {
        $body   = Get-StopBody -Data $data
        $toastB = $body
        $ntfy   = "入力待ち: $body"
    }
    'Notification' {
        # Notification フックは message フィールドに内容が入ることがある
        $msg = $null
        if ($data -and $data.message) { $msg = [string]$data.message }
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = '確認・入力待ちです' }
        $toastB = $msg
        $ntfy   = "Claude Code: $msg"
    }
    default {
        # hook_event_name が取れない場合（手動テスト等）でも動くように
        $toastB = '確認・入力待ちです'
        $ntfy   = 'Claude Code: 確認待ちです'
    }
}

Show-Toast -Title $title -Body $toastB
Send-Ntfy  -Message $ntfy
