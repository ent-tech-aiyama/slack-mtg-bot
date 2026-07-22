# Claude Code 通知フック（リモートセッション → iPhone / Apple Watch）

このリポジトリのクラウドセッション（iPhone の Claude アプリ等）で、
**Claude の返答が終わって「自分のターン」になった瞬間**に、ntfy 経由で
iPhone / Apple Watch へプッシュ通知を飛ばす仕組み。

- `../settings.json` … Stop / Notification フックの定義（毎セッション自動で読み込まれる）
- `notify-ntfy.py` … 通知本体。ntfy トピック `claude-aiyama-91dfd2c474b1` へ送信

## 通知の内容

- **Stop**（返答終了＝あなたのターン）: 会話記録から最後の返答を読み、
  「👉」で始まる行を優先、なければ先頭 100 文字 →「入力待ち: …」として送信
- **Notification**（確認・許可待ち）:「Claude Code: …」として送信

## ⚠️ 動作の前提（重要）

この環境の外向き通信はネットワークポリシーで制御されており、
**`ntfy.sh` が許可されていないと送信できない**（2026-07-22 時点ではブロック中: 403）。

有効化するには: claude.ai/code（またはアプリ）の **環境（Environment）設定 →
ネットワークアクセス** で、許可ドメインに `ntfy.sh` を追加する。
反映は新しいセッションから。ブロック中でもフックは無害（黙って失敗するだけ）。

## 動作確認

新しいセッションで「ntfy にテスト送信して」と頼む。または:

```bash
echo '{"hook_event_name":"Notification","message":"テスト"}' | python3 .claude/hooks/notify-ntfy.py
```

スマホの ntfy アプリに届けば成功（iPhone ロック中なら Apple Watch にも出る）。

## 備考

- トピック名は合言葉。リポジトリはプライベート運用（CLAUDE.md 参照）だが、
  漏れが気になる場合は `notify-ntfy.py` の `NTFY_TOPIC` を変更し、
  スマホの ntfy アプリで新トピックを購読し直す。
- Mac / Windows のローカル Claude Code 用の同様の仕組みは別途（Mac は設定済み）。
