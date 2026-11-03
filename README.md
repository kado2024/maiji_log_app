# 毎時ログ（iOS / Flutter）

1時間に1回だけ2秒の動画を撮り、1日分をつなげてVlogとして再生する日記アプリ。

- 画面：ホーム（いまの枠・お題・24時間マス）／撮影（2秒で自動停止）／Vlog再生／設定
- 保存：端末内のみ（`Documents/clips` + `index.json`）。外部送信なし
- 通知：毎時00分のローカル通知（時間帯を選択可）

## 開発

```bash
flutter pub get
flutter test                 # ロジックと画面のテスト
flutter test test_screenshots  # App Store用スクリーンショットを build/screenshots に出力
python3 tool/make_icon.py ios/Runner/Assets.xcassets/AppIcon.appiconset  # アイコン再生成
```

App Store への提出手順は [SUBMISSION.md](SUBMISSION.md) を参照。
