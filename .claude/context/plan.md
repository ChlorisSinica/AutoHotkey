<!-- USER_REQUEST: 1) Mouseのチャタリングを防止するスクリプトを作成。取り付け/取り外しが容易でハードコードを避ける仕様（Includeして該当キーを設定/宣言するだけ）。2) lib/CSharpUIA/ を導入し、ビルド確認まで行う -->

# Plan: チャタリング防止プラグイン + CSharpUIA 導入

## 1. 目的

### Feature A: チャタリング防止プラグイン

既存の `.logs/MouseChatterGuard.ahk` + `.logs/MouseKeyRouter.ahk` の設計をベースに、プロジェクトの規約に準拠した正式プラグインを作成する。

**設計原則**: Include して対象キーを宣言するだけで機能する。ハードコードを排除し、キーの追加・削除が容易。

**成功基準**:
- `Plugins/ChatterGuard.ahk` + `Plugins/KeyRouter.ahk` が存在する
- main.ahk に `#Include` と初期化コードのみで接続完了
- 対象キーの追加/削除が main.ahk の宣言テーブル変更のみで完結する
- 既存の F15/F16/F17/XButton1/XButton2/MButton のホットキー動作が維持される
- ホットキー定義が main.ahk に残り、プラグイン内にトップレベルホットキーがない（ahk-style.md 準拠）

### Feature B: CSharpUIA 導入

`lib/CSharpUIA/UiaIntegration.ahk` を main.ahk に接続し、C# 監視プロセスのビルド・動作確認を行う。

**成功基準**:
- main.ahk に `#Include` + `UiaInit()` + `OnExit("UiaCleanup")` が追加されている
- `dotnet publish` でビルドが成功する
- AHK 起動時に UiaMonitor.exe が自動起動し、共有メモリ経由で `UiaIsEditable()` が値を返す

## 2. Non-Objectives（スコープ外）

- BracketWrap.ahk の UIA 接続（別タスク）
- KeyRouter のホイール修飾・コンボ機能の実装（既存 main.ahk のホットキー構造をそのまま維持）
- IndicatorManager への ChatterGuard 設定項目追加
- UiaMonitor.exe の管理者権限対応
- CSharpUIA の FlaUI バージョンアップ

## 3. アプローチ

### Feature A: 2層アーキテクチャ

```
Layer 1: Plugins/ChatterGuard.ahk  — 純粋なデバウンスフィルタ
Layer 2: Plugins/KeyRouter.ahk     — コンボ/ルーティング/アクション実行
main.ahk                           — キー宣言テーブル + ホットキー定義
```

#### 代替案との比較

| 案 | メリット | デメリット |
|---|---|---|
| **2層分離（採用）** | 関心の分離が明確。ChatterGuard 単独でも使える | ファイル2つ |
| 1ファイル統合 | シンプル | デバウンスとルーティングが密結合 |
| デバウンスのみ | 最小限 | コンボ連打防止ができない |

#### 既存 .logs/ との差分

| 項目 | .logs/ 版 | 正式版 |
|---|---|---|
| ホットキー定義場所 | なし（呼び出し側不明） | main.ahk に集約 |
| 対象キーのハードコード | `CG_Thresholds` にグローバルで直書き | main.ahk から `CG_Init(config)` に渡す |
| プレフィックス | `CG_`, `MK_` | 同じ（互換維持） |
| ホイール修飾 | `MK_WheelMap` + `MK_OnWheel()` | 同機能を維持 |
| コンボ連打防止 | `CG_ComboThresholds` にハードコード | config 経由で渡す |

#### §3.1 状態遷移表（ChatterGuard キー状態）

```
State: { isDown: bool, lastStamp: int, threshold: int }

[Idle: isDown=false]
  ├─ RawDown → (TickCount - lastStamp < threshold) → [Idle] (チャタリング: 無視)
  ├─ RawDown → (TickCount - lastStamp >= threshold) → [Held: isDown=true] → OnCleanDown callback
  └─ RawUp → [Idle] (無視)

[Held: isDown=true]
  ├─ RawDown → [Held] (無視: 既に押下中)
  ├─ RawUp → [Idle: isDown=false] → OnCleanUp callback
  └─ CG_Stamp() → lastStamp = TickCount (外部からタイムスタンプ更新)
```

#### §3.2 KeyRouter コンボ解決フロー

```
MK_OnDown(keyName):
  1. TriggerKeys に keyName がある？
     → Yes: held キーが CG_IsHeld() で押下中？
       → Yes: コンボ成立 → MK_Exec(comboAction), held.comboUsed=true
       → No:  単独即発火 → MK_Exec(ResolveAction(keyName))
     → No:  通常キー → Up 待ち（comboUsed=false で保持）

MK_OnUp(keyName):
  1. ReleaseCallbacks あり？ → callback.Call()
  2. TriggerKeys？ → Down で処理済み、状態クリアのみ
  3. 通常キー + comboUsed=false → MK_Exec(ResolveAction(keyName))
```

#### §3.3 コールバック契約

| コールバック | シグネチャ | 設定タイミング | 呼び出し元 |
|---|---|---|---|
| `CG_OnCleanDown` | `Func(keyName)` | KeyRouter 初期化時 | ChatterGuard.CG_RawDown |
| `CG_OnCleanUp` | `Func(keyName)` | KeyRouter 初期化時 | ChatterGuard.CG_RawUp |
| `MK_ReleaseCallbacks[key]` | `Func()` | AltTabAction 等で動的登録 | KeyRouter.MK_OnUp |

### Feature B: CSharpUIA 導入

1. main.ahk に `#Include` 追加（WindowManager の後、依存なしのため位置は柔軟）
2. 初期化セクションに `UiaInit()` + `OnExit("UiaCleanup")` 追加
3. C# プロジェクトのビルド確認
4. `UIA_MONITOR_EXE` パスの確認（現在: `A_ScriptDir . "\lib\CSharpUIA\UiaMonitor\UiaMonitor.exe"`）

#### ビルドパス問題

`UiaIntegration.ahk` の `UIA_MONITOR_EXE` は `lib\CSharpUIA\UiaMonitor\UiaMonitor.exe` を想定しているが、ソースは `lib\CSharpUIA\` 直下。publish 先を合わせる必要がある。

## 4. ファイル変更一覧

| ファイル | 変更内容 |
|---|---|
| `Plugins/ChatterGuard.ahk` | **新規作成**: .logs/MouseChatterGuard.ahk をベースにハードコード排除 |
| `Plugins/KeyRouter.ahk` | **新規作成**: .logs/MouseKeyRouter.ahk をベースにハードコード排除 |
| `main.ahk` | **変更**: #Include 追加、キー設定テーブル定義、ホットキー書き換え、UIA 初期化追加 |
| `lib/CSharpUIA/UiaIntegration.ahk` | **変更**: UIA_MONITOR_EXE パス修正（必要に応じて） |

## 5. データフロー影響分析

### Feature A

```
main.ahk (設定テーブル定義)
  │
  ├─ CG_Init(thresholds)  →  ChatterGuard.ahk (状態初期化)
  ├─ CG_OnCleanDown/Up := Func("MK_OnDown"/"MK_OnUp")  →  コールバック接続
  ├─ MK_ActionMap, MK_ComboMap, MK_WheelMap 設定  →  KeyRouter.ahk (アクションテーブル)
  │
  └─ ホットキー定義 (main.ahk)
       F15::CG_RawDown("F15")  →  ChatterGuard  →  MK_OnDown  →  MK_Exec(action)
       F15 Up::CG_RawUp("F15") →  ChatterGuard  →  MK_OnUp   →  MK_Exec(action)
```

**影響を受ける既存ホットキー**: main.ahk L109-L126 の `#If (EnableMouseBtn)` セクション全体

### Feature B

```
main.ahk
  ├─ #Include lib/CSharpUIA/UiaIntegration.ahk
  ├─ UiaInit()  →  UiaStartMonitor()  →  Run UiaMonitor.exe
  │                 UiaOpenSharedMemory()  →  DllCall OpenFileMapping
  ├─ OnExit("UiaCleanup")  →  共有メモリ解放 + プロセス停止
  │
  └─ (将来) BracketWrap.ahk / 他プラグインが UiaIsEditable() 等を呼ぶ
```

## 6. リスク + ロールバック

| リスク | 影響 | 対策 |
|---|---|---|
| ChatterGuard の閾値が合わないとクリック無視 | 中 | 閾値を main.ahk で宣言（調整容易） |
| 既存ホットキーの挙動変更 | 高 | 段階的移行: まず CG 層のみ挿入、動作確認後に KR 層追加 |
| UiaMonitor.exe のビルド失敗 | 低 | .NET SDK 未インストールなら案内のみ |
| UiaMonitor.exe がサイレント失敗 | 低 | UiaIntegration.ahk は pBuf=0 時にフォールバック済み |

**ロールバック**: ChatterGuard/KeyRouter の `#Include` をコメントアウトし、元のホットキー定義に戻す。
