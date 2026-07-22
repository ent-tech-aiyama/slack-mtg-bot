# Claude Code 通知フック（Windows 用）セットアップキット

Claude Code が「確認待ち・入力待ち」になったとき、**Windows の画面通知（トースト）＋通知音**と
**スマホ（ntfy アプリ）**に通知を飛ばすためのセットアップ一式です。
Mac 側は設定済みで、これは会社などの Windows マシン用です。

- `claude-notify.ps1` … 通知フック本体（Notification / Stop の両方に対応）
- `settings.example.json` … `~/.claude/settings.json` に入れるフック設定の見本
- `Install.ps1` … 上記を自動で配置・設定・テストするインストーラ

> ⚠️ このキットは **Windows 上の PowerShell** で実行するものです。
> Linux のリモートセッション（Claude Code on the web など）からは実機のトースト通知や
> ntfy 送信は行えません。**実際の設定とテストは Windows マシン上で行ってください。**

---

## いちばん簡単な方法（おすすめ）

Windows でこのフォルダを開き、PowerShell で次を実行するだけです:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

`Install.ps1` がやること:

1. `claude-notify.ps1` を `%USERPROFILE%\.claude\hooks\` にコピー
2. `%USERPROFILE%\.claude\settings.json` に **Notification** と **Stop** フックを追記
   （既存の設定・他のフックは壊さず保持。上書き前に `settings.json.bak` を作成）
3. テスト実行（画面通知 + ntfy 送信を確認）

オプション:

```powershell
# BurntToast も一緒に入れる（よりきれいなトースト）
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -InstallBurntToast

# 最後のテスト送信をスキップ
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -SkipTest
```

Windows の Claude Code に頼む場合は、このフォルダを読ませて次のように依頼してください:

> このフォルダの Install.ps1 を実行して、この Windows マシンに Claude Code の通知フックを
> 設定してください。設定後に必ずテストして、画面通知と ntfy 送信が両方動くことを確認してください。

---

## 手動で設定する場合

1. `claude-notify.ps1` を `%USERPROFILE%\.claude\hooks\claude-notify.ps1` に置く。
2. `settings.example.json` の `<ユーザー名>` を自分の Windows ユーザー名に置き換え、
   その `hooks` ブロックを `%USERPROFILE%\.claude\settings.json` に**追記**する
   （既存の設定は消さない）。
3. Claude Code で `/hooks` を開くか、Claude Code を再起動して反映する。

---

## 通知の内容

### Notification フック（確認・許可待ち）
- 画面: `Claude Code` / `確認・入力待ちです`（フックが `message` を渡す場合はその内容）
- ntfy: `Claude Code: 確認・入力待ちです`

### Stop フック（返答が終わって入力待ち）
固定文ではなく **「Claude の最後の返答」から通知文を作ります**（Mac 側と同じ挙動）:

- フックが受け取る JSON の `transcript_path`（会話記録 JSONL）を読み、
  最後の assistant メッセージのテキストを取り出す
- そのうち **「👉」で始まる行**があればそれを優先
- なければ本文の先頭 **100 文字**を使う
- それを本文にして、画面通知と ntfy（`入力待ち: …`）に送る

`transcript_path` が取れない・読めない場合は、`返答が終わりました。入力待ちです` に
自動でフォールバックします（最低限 ntfy 通知は飛びます）。

---

## トースト通知の仕組み（フォールバック順）

`claude-notify.ps1` は次の順で画面通知を試します:

1. **BurntToast**（インストール済みなら使用）
2. **WinRT ネイティブトースト**（Windows PowerShell 5.1 でも動作）
3. **`msg.exe`**（最後の手段）

さらに、トーストに音が付かない環境向けに `SystemSounds.Asterisk` で通知音も鳴らします。
`powershell`（Windows PowerShell 5.1）で動くように書いてあるため、`pwsh`（PowerShell 7）が
無くても動作します。

---

## ntfy のトピック名（Mac と共通）

```
claude-aiyama-91dfd2c474b1
```

- スマホの ntfy アプリでこのトピックを購読済み（Mac 設定時に購読）。
- **このトピック名は合言葉なので、他人に教えない。**
- トピックを変えたい場合は `claude-notify.ps1` 冒頭の `$NtfyTopic` を書き換える。

---

## コマンド単体テスト

`Install.ps1` を使わずにフック本体だけ試すには:

```powershell
# Notification フック相当
'{"hook_event_name":"Notification","message":"テストです"}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\claude-notify.ps1"

# Stop フック相当（transcript_path を実ファイルに差し替えると本文抽出も試せる）
'{"hook_event_name":"Stop"}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\claude-notify.ps1"
```

画面右下に通知が出て、スマホの ntfy に届けば成功です。

---

## 設定後の確認

1. コマンド単体のテストが通ること
2. `settings.json` が正しい JSON であること（壊れていると設定全体が無効になる）
3. 反映されない場合は Claude Code で `/hooks` を一度開くか、Claude Code を再起動する

---

## あわせて：スリープ設定の確認（重要）

PC がスリープすると Claude の作業自体が止まり、通知も飛びません。
Windows 側でもスリープ設定を確認してください（Mac は設定済み：電源接続時スリープなし）。

1. スタート → **設定** → **システム** → **電源**（ノート PC は「電源とバッテリー」）
2. **「画面とスリープ」** を開く
3. **「電源接続時に、デバイスをスリープ状態にする」→「なし」** に変更
   - 画面オフの時間は好きなままでよい（画面が消えても作業は続く）
   - バッテリー駆動時のスリープはそのままでよい（電池保護）
