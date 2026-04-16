# PowerPoint ソーススキャン セットアップガイド

## 概要

PowerPoint 上で `Ctrl+Alt+E` を押すと、PowerPoint Source Manager が開きます。
manager 内の `Scan` / `Re-scan` から、プレゼンテーション内に埋め込まれた
画像の元ファイルを探索できます。検索には次の 3 つのバックエンドをこの順で
使用します。

1. **Everything** もっとも高速。推奨
2. **Windows Desktop Search** Windows 標準。速度は中程度
3. **Directory scan** フォールバック。もっとも低速

---

## 1. Everything（推奨）

[Everything](https://www.voidtools.com/) は、ファイルシステム全体をリアルタイムに
インデックスする検索ツールです。スキャンでは CLI ツール `es.exe` を使い、
ファイルサイズによる候補検索を即座に実行します。

### インストール

1. <https://www.voidtools.com/downloads/> から **Everything** をダウンロード
2. 基本的には既定設定のままインストール
3. 同じページから **Everything Command-line Interface (ES)** もダウンロード
4. `es.exe` を次のいずれかに配置
   - `C:\Program Files\Everything\es.exe`
   - `C:\Program Files (x86)\Everything\es.exe`
   - または `PATH` が通っている任意のディレクトリ
5. ターミナルで `es.exe --version` を実行して確認

### インデックス確認

```text
es.exe size:=12345
```

結果がすぐ返ってくれば Everything は正常に動作しています。

### 補足

- スキャン中は Everything 本体またはサービスが起動している必要があります
- 初回のインデックス作成には数分かかることがあります
- 更新自体は通常ほぼ即時です
- ネットワークドライブも Everything の設定から追加できます
  `Options > Indexes > Folders`

---

## 2. Windows Desktop Search（標準フォールバック）

WDS は Windows に標準搭載されており、通常はユーザーの主要フォルダを
インデックスしています。追加インストールは不要ですが、すべての場所が
対象になるとは限りません。

### インデックス範囲の確認

1. **設定 > プライバシーとセキュリティ > Windows の検索** を開く
2. **拡張** を選び、PC 全体をインデックス対象にするのを推奨
3. または「検索場所のカスタマイズ」で個別フォルダを追加

### 制約

- Everything より遅いです
  ADODB 経由の SQL クエリを使います
- 外付けドライブやネットワークパスはインデックスされない場合があります
- ファイル変更がインデックスに反映されるまで数分遅れることがあります

---

## 3. Directory scan（最終フォールバック）

Everything と WDS のどちらでも見つからない場合、次のディレクトリを再帰的に
探索します。

- pptx ファイルのあるフォルダとその親フォルダ
- `%USERPROFILE%\Desktop`
- `%USERPROFILE%\Downloads`
- `%USERPROFILE%\Pictures`
- `%USERPROFILE%\Documents`

この範囲の外にあるファイルは Directory scan では見つかりません。網羅性を
重視するなら Everything の導入を推奨します。

---

## 除外パス

誤検出を避けるため、次のパスは検索結果から自動的に除外されます。

| パス | 理由 |
|------|------|
| `%TEMP%\ppt_scan_*` | スキャン自身が展開した一時メディア |
| `<pptBaseName>_sources\` | 既にエクスポート済みのソース格納先 |
| `%LOCALAPPDATA%\Google\DriveFS\` | Google Drive の揮発キャッシュ |
| `%LOCALAPPDATA%\Microsoft\OneDrive\cache\` | OneDrive の内部キャッシュ |
| `%TEMP%` | すべての一時ファイル |

---

## PowerShell 依存関係

現行の source manager は PowerShell / WPF ベースです。
追加の Python 環境は不要です。

### 補足

- 画像プレビューは WPF の `Image` で表示しており、追加ライブラリは不要です
- Windows 標準の PowerShell が使える環境を前提にしています

---

## 使い方

1. 保存済みの `.pptx` を PowerPoint で開く
2. `Ctrl+Alt+E` で source manager を開く
3. 必要に応じて manager 内の `Scan` / `Re-scan` を実行する
4. 完了後、表で結果を確認する
5. `Ctrl+Alt+Q` で選択図形のソース情報を表示する
6. manager 内の `Export Sources` で解決済みは `<pptBaseName>_sources/resolved/`、
   未解決は `<pptBaseName>_sources/_unresolved/` に保存する
   `sources_list.json` は `<pptBaseName>_sources/` 直下に保存される
7. `Ctrl+Alt+F1` でヘルプのショートカット一覧を表示する

## 実機確認シナリオ

1. 同じ `pptx` で manager が開いている状態で `Ctrl+Alt+E` を押し、既存 window が前面化されること
2. 別の `pptx` で `Ctrl+Alt+E` を押し、多重起動せず拒否メッセージになること
3. `Manual Pick` 実行後に `Re-scan` しても `RETRO_MANUAL` row が自動上書きされないこと
4. 画像を削除したあと `Re-scan` すると row と manifest entry が消えること
5. 画像を追加したあと `Re-scan` すると新規 row が増えること
