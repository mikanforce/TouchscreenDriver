# TouchscreenDriver for Corsair Xeneon Edge

macOSでCorsair Xeneon Edgeのタッチスクリーンを動かすドライバです。  
タッチ入力をマウスクリックに変換し、拡張ディスプレイ上でのシングル・ダブルクリック操作を可能にします。

> **開発**: [mikanforce](https://github.com/mikanforce) × [Claude](https://claude.ai) (Anthropic AI)

---

## 特徴

- タッチした位置に正確にクリックを送信
- **シングルタップ** → クリック
- **素早く2回タップ（300ms以内）** → ダブルクリック
- HID排他キャプチャ（ダブル入力防止）
- マルチモニター対応・自動ディスプレイ検出
- クリック後にカーソルを元の位置に自動復帰
- 解像度変更・ディスプレイ再配置に自動対応

---

## 動作環境

- macOS 10.15 (Catalina) 以降
- Xcode Command Line Tools
- Corsair Xeneon Edge（USB-C接続）

---

## インストール

```bash
git clone https://github.com/mikanforce/TouchscreenDriver.git
cd TouchscreenDriver
./install.sh
```

インストール後、自動的にドライバが起動し、ログイン時に自動起動するよう設定されます。

### 権限の付与（初回のみ）

初回起動時にmacOSが2つの権限を要求します：

1. **アクセシビリティ**  
   `システム設定` → `プライバシーとセキュリティ` → `アクセシビリティ` → TouchscreenDriverを追加

2. **入力監視**  
   `システム設定` → `プライバシーとセキュリティ` → `入力監視` → TouchscreenDriverを追加

権限付与後、ドライバを再起動してください。

---

## アンインストール

```bash
./uninstall.sh
```

---

## 操作コマンド

```bash
# 状態確認
pgrep -f TouchscreenDriver && echo "Running" || echo "Stopped"

# ログ確認
tail -f /tmp/touchscreendriver.log

# 停止
launchctl unload ~/Library/LaunchAgents/com.ymlaine.touchscreendriver.plist

# 起動
launchctl load ~/Library/LaunchAgents/com.ymlaine.touchscreendriver.plist
```

---

## カスタマイズ

`TouchscreenDriver.swift` の冒頭部分で調整できます：

```swift
// ダブルクリック判定時間（デフォルト: 300ms）
let doubleClickInterval: TimeInterval = 0.3

// ダブルクリック判定距離（デフォルト: 20px以内）
let doubleClickDistance: CGFloat = 20.0

// debounce（誤クリック防止の待ち時間、デフォルト: 50ms）
let debounceInterval: TimeInterval = 0.05
```

変更後は再ビルドが必要です：

```bash
./install.sh
```

---

## トラブルシューティング

### 「タッチスクリーンが見つかりません」
- USB-Cで接続されているか確認
- `システム情報` → `USB` でデバイスが認識されているか確認

### 「アクセシビリティ権限が必要です」と繰り返し表示される
- アクセシビリティの一覧からTouchscreenDriverを一度削除して再追加
- 再コンパイル後は権限の再付与が必要です

### iCUEと競合する
- iCUEを終了してからドライバを起動してください
- どうしても共存させたい場合は `captureMode = .shared` に変更（ダブルクリックが発生する場合あり）

### クリック位置がズレる
```bash
./run_analyzer.sh
```
で画面四隅をタッチしてX/Y最大値を確認し、`TouchscreenDriver.swift`の値を更新してください。

---

## ハードウェア情報

```
タッチスクリーンコントローラ:
  Vendor ID:  0x27c0
  Product ID: 0x0859
  製造元: wch.cn

ディスプレイ:
  ネイティブ解像度: 2560x720 (32:9)
  推奨スケーリング: 1920x540（文字が読みやすい）
```

---

## ライセンス

MIT License

---

## 謝辞

元のドライバ実装: [ymlaine/TouchscreenDriver](https://github.com/ymlaine/TouchscreenDriver)  
ダブルクリック対応・日本語化: [mikanforce](https://github.com/mikanforce)
