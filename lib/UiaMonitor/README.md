# UiaMonitor — UIA 監視プロセス + AHK v1.1 連携

## 概要

C# 常駐プロセスが UI Automation でフォーカス要素・テキスト選択状態を監視し，
共有メモリ（MemoryMappedFile）経由で AHK v1.1 スクリプトに即時提供します．

```
[C# UiaMonitor.exe]                [AHK v1.1 UiaIntegration.ahk]
 UIA FocusChanged イベント           ホットキー押下時
 TextPattern 選択ポーリング(60ms)      ↓
        │                         NumGet で共有メモリ読取 (< 0.1ms)
        ↓                              ↓
 共有メモリに状態書込み              isEditable / hasSelection で分岐
```

## 共有メモリ構造（16バイト）

| Offset | Size | Field          | Values                                      |
|--------|------|----------------|---------------------------------------------|
| 0      | 1    | isTextEditable | 0=No, 1=Yes                                 |
| 1      | 1    | hasSelection   | 0=No, 1=Yes                                 |
| 2      | 1    | controlType    | 0=Edit, 1=RichEdit, 2=Document, 3=Browser, 0xFF=Unknown |
| 3      | 1    | (reserved)     |                                              |
| 4      | 4    | processId      | フォーカス先プロセスID                        |
| 8      | 1    | shutdownSignal | 0=通常, 1=シャットダウン要求                  |

## ビルド手順

### 前提条件

- .NET 6.0 SDK 以上
- Windows 11

### ビルド

```powershell
cd UiaMonitor
dotnet restore
dotnet publish -c Release -r win-x64 --self-contained false -o ./publish
```

自己完結型（.NET ランタイム不要）にする場合：

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -o ./publish
```

`./publish/UiaMonitor.exe` が生成されます．

## セットアップ

1. `publish/` フォルダの中身を任意の場所に配置
2. `ahk/UiaIntegration.ahk` を開き，`UIA_MONITOR_EXE` のパスを実際のパスに変更

```ahk
global UIA_MONITOR_EXE := "C:\Tools\UiaMonitor\UiaMonitor.exe"
```

3. `UiaIntegration.ahk` を実行

## 管理者権限について

管理者権限で動作するアプリ（タスクマネージャ等）の状態も取得する場合：

1. `app.manifest` の `requestedExecutionLevel` を `requireAdministrator` に変更して再ビルド
2. AHK スクリプトも管理者権限で実行

## 提供されるホットキー例

| ホットキー   | 選択中                    | 未選択（テキスト欄）          | テキスト欄外   |
|-------------|--------------------------|------------------------------|---------------|
| `(` `[` `{` | 選択テキストを括弧で囲む    | 括弧ペア入力+カーソル中移動   | 通常入力       |
| `Ctrl+Shift+C` | 通常コピー              | 行全体コピー                  | パススルー     |
| `Ctrl+Shift+X` | 通常カット              | 行全体カット                  | パススルー     |
| `Ctrl+Shift+D` | 選択テキスト複製         | 行複製                        | パススルー     |

## カスタマイズ

### AHK 側で使える関数

```ahk
; 個別取得
UiaIsEditable()      ; => 0 or 1
UiaHasSelection()    ; => 0 or 1
UiaControlType()     ; => 0, 1, 2, 3, or 0xFF
UiaProcessId()       ; => PID

; 一括取得
UiaGetState(isEd, hasSel, ctrlType)
```

### ポーリング間隔の調整

`MonitorService.cs` の `SelectionPollIntervalMs` を変更（デフォルト: 60ms）．
短くすると応答性向上，長くすると CPU 負荷軽減．

## トラブルシューティング

- **共有メモリが開けない** → UiaMonitor.exe が起動しているか確認
- **特定アプリで isEditable が 0 のまま** → そのアプリが UIA 非対応の可能性．`controlType = 0xFF` の場合はフォールバック処理を検討
- **選択状態の反映が遅い** → `SelectionPollIntervalMs` を小さくする
- **CPU 負荷が高い** → `SelectionPollIntervalMs` を大きくする，またはテキスト欄以外でポーリングが止まっているか確認
