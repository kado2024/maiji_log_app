# おなじ時刻（iOS / Flutter）

毎日「決めた時刻」に「決めた場所」を2秒だけ撮り、日ごとの変化を残す定点観測アプリ。
（リポジトリ名・Dartパッケージ名・Bundle ID は旧名「毎時ログ」のまま）

- 定点時刻：最大3つ（例：07:30 窓の外）。撮影できるのは時刻の15分前〜45分後、1日1回
- 撮影：2秒で自動停止。前回のコマを半透明で重ねる構図ガイド＋三分割グリッド
- アーカイブ：定点時刻ごとの月カレンダー。1週間／1か月／3か月／すべてを日付順に連続再生（1日2秒・1秒・0.5秒）
- 比較：2日を選んでドラッグで見比べ
- 書き出し：日付を焼き込んだ1本の mp4（AVFoundation、`ios/Runner/AppDelegate.swift` の `TeitenMediaPlugin`）→「写真」に保存／共有
- 通知：定点時刻ごとの毎日のローカル通知
- 保存：端末内のみ（`Documents/teiten` + `index.json`）。外部送信なし

## 開発

```bash
flutter pub get
flutter test                 # ロジックと画面のテスト
flutter test test_screenshots  # App Store用スクリーンショットを build/screenshots に出力
python3 tool/make_icon.py ios/Runner/Assets.xcassets/AppIcon.appiconset  # アイコン再生成
```

App Store への提出手順は [SUBMISSION.md](SUBMISSION.md) を参照。
