# claude-image-gallery

Claude Code が生成・出力した画像を、ブラウザの**ローカルギャラリーに自動集約**する hook プラグイン。

CLI では生成された画像をその場で確認できない、という問題を解決します。画像ごとに Preview を開く方式と違ってウィンドウが溜まらず、フォーカスも奪いません。

## 動作

```
ツール(Write / Bash)が画像を出力
  → PostToolUse hook がパスを検出
  → ~/.claude/image-gallery/index.html(静的HTML)を再生成
  → ギャラリータブが開いていれば AppleScript でそのタブだけリロード
  → 開いていなければバックグラウンド(open -g)で開く
```

サーバーもポーリングも無し。ページが更新されるのは新着画像があった瞬間だけです。

### ギャラリーの機能

- **モーダル拡大** — カードクリックで拡大、`←` `→` で前後移動、`Esc` / 背景クリックで閉じる
- **ページネーション** — 50件/ページ(最新順、最新カードは緑枠)
- **パスコピー** — 各カードとモーダルの copy ボタン。`open -R <ペースト>` で Finder 表示
- **自動整理** — 削除済みファイルのエントリは実行のたびにプルーニング。読み込みに失敗した画像のカードは自動非表示。履歴は最大500件、ページには最新200件
- **重複排除** — パス+mtime で管理。同じ画像は再追加されず、再生成(mtime 変化)は先頭に再登場

## 要件

- **macOS**(`stat -f` / `tail -r` / `open` / AppleScript を使用。Linux / Windows 非対応)
- **jq**(`brew install jq`)
- タブの自動リロードは **Google Chrome**(Chromium 系なら概ね動作)。他ブラウザでも画像収集とギャラリー生成は動きますが、リロードは効かず開き直しになります
- 対応拡張子: png / jpg / jpeg / gif / webp / bmp / tiff / heic / svg

## インストール

```
/plugin marketplace add namasugi/claude-image-gallery
/plugin install image-gallery@image-gallery
```

以後、Claude Code が画像を生成すると自動でギャラリーが開きます。手動で開く場合:

```bash
open ~/.claude/image-gallery/index.html
```

## 状態ファイル

ギャラリーの実体はプラグイン外の `~/.claude/image-gallery/` に置かれます(プラグイン更新で消えないように):

| ファイル | 役割 |
|---|---|
| `index.html` | ギャラリー本体(hook が再生成) |
| `entries.tsv` | 画像の履歴(mtime + 絶対パス) |
| `seen.txt` | 重複排除キー |

履歴をリセットしたい場合はディレクトリごと削除して構いません。

## 権限について

初回のタブリロード時、macOS がターミナルアプリに対して「"Google Chrome" を制御することを許可しますか」と確認する場合があります。許可すると以後は自動で動きます。

## License

MIT
