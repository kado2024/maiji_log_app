# App Store 提出手順（毎時ログ）

iOSアプリのビルドと提出には **macOS（Xcode）** と **Apple Developer Program（有料・年会費）** が必要です。
このリポジトリには、Macを持っていなくても GitHub Actions の Mac 環境でビルド→アップロード→審査提出まで行う仕組みを入れてあります。

---

## 0. 事前に用意するもの

- Apple Developer Program のメンバーシップ（https://developer.apple.com/programs/ ）
- GitHub アカウント
- 実機テスト用の iPhone（TestFlight アプリを入れておく）

## 1. Bundle ID を決める

初期値は `com.kado2024.maijilog` です。すでに他の人が使っていると登録できないので、自分のものに変えます（例：`com.あなたの名前.maijilog`）。

```bash
grep -rl "com.kado2024.maijilog" ios | xargs sed -i "" "s/com\.kado2024\.maijilog/com.yourname.maijilog/g"
```

（Linux の場合は `sed -i ''` を `sed -i` に）

## 2. サポートページとプライバシーポリシー

`docs/privacy.md` と `docs/support.md` は GitHub 上でそのまま公開され、ストア掲載文の URL（`ios/fastlane/metadata/ja/*_url.txt`）もそこを指しています。問い合わせ先は GitHub Issues です。追加の作業はありません。

## 3. Apple Developer で App ID を登録

https://developer.apple.com/account/resources/identifiers → ＋ → App IDs → App
- Description：毎時ログ
- Bundle ID（Explicit）：手順1で決めたもの
- Capabilities：追加不要（通知は端末内のローカル通知なので Push Notifications も不要）

## 4. App Store Connect でアプリを作成

https://appstoreconnect.apple.com → アプリ → ＋ → 新規App
- プラットフォーム：iOS
- 名前：`毎時ログ - 1時間に2秒の日記`（使われていたら少し変える。`metadata/ja/name.txt` も同じにする）
- プライマリ言語：日本語
- バンドルID：手順3のもの
- SKU：`maijilog001` など任意

## 5. App Store Connect API キーを作る

App Store Connect → ユーザとアクセス → 統合 → App Store Connect API → チームキー → ＋
- アクセス：**Admin**（配布用署名をクラウドで行うために必要。App Manager では署名できません）
- 作成後、**.p8 ファイルをダウンロード**（1回しかダウンロードできません）
- 「キーID」と「Issuer ID」を控える

Team ID は https://developer.apple.com/account → メンバーシップの詳細 にある10文字の英数字です。

## 6. GitHub に Secrets を登録

リポジトリの Settings → Secrets and variables → Actions → New repository secret

| 名前 | 値 |
|---|---|
| `ASC_KEY_ID` | キーID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | .p8 を base64 にした文字列（Mac：`base64 -i AuthKey_XXXX.p8 \| pbcopy`） |
| `APPLE_TEAM_ID` | Team ID |

## 7. TestFlight で実機テスト

GitHub → Actions → **iOS release** → Run workflow → lane：`beta`

10〜20分でビルドが App Store Connect に届きます（処理にさらに10〜30分）。
App Store Connect → TestFlight で自分をテスターに追加し、iPhone の TestFlight アプリからインストールして次を確認します。

- [ ] カメラとマイクの許可ダイアログが出て、2秒で録画が止まる
- [ ] 「このコマを使う」でホームのマスに入る／撮り直しで置き換わる
- [ ] Vlog再生（タップで前後移動、音のオン/オフ）
- [ ] 設定で通知をオン → 次の00分に通知が来る
- [ ] アプリを終了して開き直してもコマが残っている

## 8. App Store Connect で手入力する項目

API からは設定しないので、画面で入力します。

- **Appのプライバシー**：「データを収集しない」を選んで公開
- **年齢制限指定**：質問にすべて「なし／いいえ」で回答
- **価格および配信状況**：無料、配信する国（日本など）
- **App Review に関する情報**：連絡先の氏名・電話番号・メール（審査メモは自動で入ります）

## 9. 審査に提出

GitHub → Actions → **iOS release** → Run workflow → lane：`release`、**Submit for App Review にチェック**

これで次がまとめて行われます。
- 新しいビルドのアップロード
- 説明文・キーワード・サブタイトル・プロモーションテキスト・カテゴリ・URL の反映（`ios/fastlane/metadata/ja`）
- スクリーンショット4枚のアップロード（`ios/fastlane/screenshots/ja`、6.9インチ 1320×2868）
- 審査への提出（承認後は手動リリース）

審査は通常24〜48時間です。結果は App Store Connect とメールで届きます。承認されたら App Store Connect で「このバージョンをリリース」を押すと公開されます。

---

## Mac を持っている場合（GitHub Actions を使わない方法）

```bash
flutter build ipa --release
```

`build/ios/archive/Runner.xcarchive` を Xcode で開き、Organizer → Distribute App → App Store Connect → Upload。
署名は Xcode の Runner ターゲット → Signing & Capabilities で Team を選び「Automatically manage signing」をオン。
ストア情報とスクリーンショットは App Store Connect の画面で入力するか、`cd ios && bundle exec fastlane deliver` で送れます。

## 2回目以降のアップデート

`pubspec.yaml` の `version: 1.0.0+1` の左側（1.0.1 など）を上げてから、手順9をもう一度実行します。ビルド番号は GitHub Actions の実行番号が自動で入ります。
