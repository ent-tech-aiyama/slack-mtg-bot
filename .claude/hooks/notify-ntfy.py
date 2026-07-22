#!/usr/bin/env python3
"""Claude Code 通知フック（リモートセッション用）

Stop フック（返答が終わって入力待ち）と Notification フック（確認・許可待ち）の
両方から呼ばれ、ntfy へ通知を送る。スマホの ntfy アプリ（トピック購読済み）経由で
iPhone / Apple Watch に届く。

Stop のときは固定文ではなく「Claude の最後の返答」から通知文を作る:
  - stdin の JSON の transcript_path（会話記録 JSONL）を読み、
    最後の assistant メッセージのテキストを取り出す
  - 「👉」で始まる行があればそれを優先
  - なければ本文の先頭 100 文字を使う

注意: この環境の外向き通信はネットワークポリシーで制御されている。
ntfy.sh が許可されていない場合、送信は失敗するが本スクリプトは黙って終了する
（セッションの動作は一切妨げない）。
"""

import json
import subprocess
import sys

NTFY_TOPIC = "claude-aiyama-91dfd2c474b1"  # Mac と共通のトピック（合言葉）
NTFY_URL = f"https://ntfy.sh/{NTFY_TOPIC}"
MAX_LEN = 100
ARROW = "\U0001F449"  # 👉


def last_assistant_text(transcript_path):
    """JSONL の会話記録から最後の assistant テキストを取り出す。"""
    if not transcript_path:
        return None
    text = None
    try:
        with open(transcript_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if obj.get("type") != "assistant":
                    continue
                content = (obj.get("message") or {}).get("content")
                if isinstance(content, str):
                    if content.strip():
                        text = content
                    continue
                if isinstance(content, list):
                    parts = [
                        b.get("text", "")
                        for b in content
                        if isinstance(b, dict) and b.get("type") == "text"
                    ]
                    joined = "\n".join(p for p in parts if p)
                    if joined.strip():
                        text = joined
    except OSError:
        return None
    return text


def clip(s):
    s = s.strip()
    return s if len(s) <= MAX_LEN else s[:MAX_LEN] + "…"


def build_message(data):
    event = (data or {}).get("hook_event_name", "")
    if event == "Stop":
        text = last_assistant_text((data or {}).get("transcript_path"))
        if text:
            for line in text.splitlines():
                t = line.strip()
                if t.startswith(ARROW):
                    return "入力待ち: " + clip(t)
            flat = " ".join(text.split())
            return "入力待ち: " + clip(flat)
        return "Claudeの返答が終わりました。入力待ちです"
    if event == "Notification":
        msg = (data or {}).get("message") or "確認・入力待ちです"
        return "Claude Code: " + clip(str(msg))
    return "Claude Code: 確認待ちです"


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}

    message = build_message(data)

    # curl はこの環境のプロキシ/CA 設定を既に読めるので、送信は curl に任せる。
    # ネットワークポリシーで ntfy.sh が未許可なら失敗するが、黙って成功終了する。
    try:
        subprocess.run(
            [
                "curl", "-sS", "-m", "10",
                "-H", "Title: Claude Code",
                "-H", "Tags: speech_balloon",
                "--data-binary", message.encode("utf-8"),
                NTFY_URL,
            ],
            input=None,
            capture_output=True,
            timeout=15,
        )
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
