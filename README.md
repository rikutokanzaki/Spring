# Spring - ハニーポットシステム切替運用フレームワーク

Springは、Sakuraをベースに自動モード切替機能を追加した拡張版ハニーポットシステムです。Sakura、Yozakura、Tsubomiの3つのモードを自動的にローテーションすることで、多様な攻撃パターンの収集を実現します。

## 概要

Springは以下の4層構造で構成されています：

### 1. Dispatcher

- **Paramiko（SSH）**: SSH接続を受け付け、認証・コマンド実行を監視して適切なハニーポットへルーティング
  - **ModeManager**: Launcher APIから現在のモードを定期的に取得し、振り分けロジックを動的に切り替え
- **OpenResty（HTTP）**: Luaスクリプトによる動的リクエスト解析と振り分け
  - **worker_init.lua**: モード情報の初期化
  - **log_mode_fallback.lua**: モード切替時のフォールバック処理

### 2. Launcher

- Docker コンテナの動的起動・停止を管理
- **ModeController**: 3つのモード間を自動ローテーション（17分間隔）
  - **Sakuraモード**: Heraldingのみ起動、動的検知で追加起動
  - **Yozakuraモード**: 全ハニーポット常時起動
  - **Tsubomiモード**: H0neytr4pとCowrieのみ起動
- セッション追跡による自動タイムアウト機能
- REST API経由でモード状態を提供

### 3. Layers

- **Active Layer（能動型）**
  - **Heralding**: SSH/HTTPなど複数プロトコルの認証試行を記録
- **Passive Layer（受動型）**
  - **Cowrie**: SSH MITMハニーポット（高リスク攻撃者向け）
  - **Wordpot**: WordPress特化型ハニーポット
  - **H0neytr4p**: Web攻撃全般を記録するローインタラクション型

### 4. ELK Stack

- **Elasticsearch**: ログデータの保存・検索
- **Logstash**: 各ハニーポットからのログを正規化・集約
- **Kibana**: ダッシュボードによる可視化

## アーキテクチャ

```
攻撃者
  ↓
┌─────────────────────────────────────┐
│ Dispatcher                          │
│  - Paramiko (SSH:22) + ModeManager  │
│  - OpenResty (HTTP:80) + Mode Lua   │
└─────────────────────────────────────┘
  ↓ モード別振り分け
┌─────────────────────────────────────┐
│ Launcher (Port :5000)               │
│  - ModeController (duration: 17min) │
│  - Docker Management                │
│  - Session Manager                  │
└─────────────────────────────────────┘
  ↓ モード別コンテナ起動
┌──────────────────────────────────────┐
│ Honeypots                            │
│  Sakura:   Heralding                 │
│  Yozakura: All                       │
│  Tsubomi:  H0neytr4p + Cowrie        │
└──────────────────────────────────────┘
  ↓ ログ出力
┌──────────────────────────────────────┐
│ ELK Stack                            │
│  - Elasticsearch                     │
│  - Logstash                          │
│  - Kibana                            │
└──────────────────────────────────────┘
```

## 主な特徴

### モード切替機能

**自動ローテーション（17分間隔）**

1. **Sakuraモード（省リソース）**

- Heraldingのみ起動
- 攻撃検知時に追加ハニーポット起動
- セッションタイムアウト5分で自動停止

2. **Yozakuraモード（フル稼働）**

- 全ハニーポット常時起動（Heralding, Wordpot, H0neytr4p, Cowrie）
- 全ての攻撃パターンを記録
- persist=True で停止しない

3. **Tsubomiモード（特定ターゲット）**

- H0neytr4pとCowrieのみ起動
- 高度な攻撃者をターゲット
- HeraldigとWordpotは停止

### モード同期メカニズム

- **Launcher ModeController**: 17分ごとにモードをローテーション
- **Paramiko ModeManager**: 10秒ごとにLauncher APIをポーリングしてモード取得
- **OpenResty Lua**: Launcherエンドポイントから動的にモードを参照

### SSH振り分けロジック

1. Paramiko Dispatcherで認証情報を記録
2. 現在のモードを取得（ModeManager）
3. モードに応じた振り分け処理
   - Sakura: 攻撃検知時にCowrie起動
   - Yozakura: 常にCowrie接続
   - Tsubomi: 直接Cowrie転送

### HTTP振り分けロジック

1. OpenRestyのLuaスクリプトでリクエストを解析
2. モード情報を確認
3. モード別ルーティング
   - Sakura: パターンマッチで動的起動
   - Yozakura: 全ハニーポット稼働
   - Tsubomi: H0neytr4pのみ

## 構成ファイル

### ディレクトリ構造

```
Spring/
├── install.sh               # インストールスクリプト
├── uninstall.sh             # アンインストール・バックアップスクリプト
├── .env                     # 環境変数設定
├── compose/                 # Docker Composeプロファイル
│     ├── standard.yml       # 全機能有効
│     ├── ssh.yml            # SSHのみ
│     ├── http.yml           # HTTPのみ
│     └── debug-ssh.yml      # Cowrieデバッグポート公開
├── dispatcher/
│     ├── paramiko/          # SSHリバースプロキシ
│     │     ├── Dockerfile
│     │     ├── requirements.txt
│     │     ├── config/
│     │     │     ├── user.txt
│     │     │     └── motd.txt
│     │     └── src/
│     │           ├── main.py
│     │           ├── mode/                  # モード管理
│     │           │     └── mode_manager.py
│     │           ├── auth/
│     │           ├── connector/
│     │           ├── session/
│     │           ├── detector/
│     │           ├── reader/
│     │           ├── notifier/
│     │           └── utils/
│     └── openresty/         # HTTPリバースプロキシ
│           ├── Dockerfile
│           ├── nginx.conf
│           ├── conf.d/
│           │     └── http.conf
│           └── lua/
│                 ├── detect.lua
│                 ├── worker_init.lua
│                 └── log_mode_fallback.lua
├── launcher/
│     ├── Dockerfile
│     ├── requirements.txt
│     ├── src/
│     │     └── launch.py
│     └── app/
│           ├── routes.py                    # REST API定義
│           ├── controllers/
│           │     ├── docker_manager.py
│           │     ├── session_manager.py
│           │     └── mode_controller.py     # モード制御
│           ├── utils/
│           │     └── flatten.py
│           ├── static/
│           └── templates/
├── layers/
│     └── core/
│           └── config/
│                 └── userdb.txt             # Cowrie認証
├── elk/
│     ├── logstash/
│     │     └── logstash.conf
│     ├── kibana/
│     │     └── export.ndjson
│     └── metricbeat/
│           └── metricbeat.yml
└── data/                                    # 各ハニーポットのログ出力先
      ├── paramiko/
      ├── openresty/
      ├── heralding/
      ├── cowrie/
      ├── wordpot/
      └── h0neytr4p/
```

## インストール

### 前提条件

- Docker & Docker Compose
- sudo権限
- ポート22, 80, 5000が利用可能

### 手順

#### 1. **環境変数設定**

`.env`ファイルを編集：

```bash
SPRING_DATA_PATH=../data
ARCHIVE_DATA_PATH=/path/to/archive
ALLOWED_NETWORKS=192.168.1.0/24
HOST_NAME=svr01
ELASTIC_PASSWORD=YourPassword
KIBANA_PASSWORD=YourPassword
STACK_VERSION=8.7.1
```

#### 2. **インストール実行**

```bash
./install.sh
```

#### 3. **プロファイル選択**

インストールスクリプトが起動時に以下から選択を求めます：

- `standard.yml`: SSH + HTTP（推奨）
- `ssh.yml`: SSH のみ
- `http.yml`: HTTP のみ
- `debug-ssh.yml`: Cowrieデバッグポート公開（デバッグ用）

#### 4. **動作確認**

```bash
docker compose -f compose/standard.yml ps
curl http://localhost:5000/current-mode  # 現在のモード確認
```

## 使用方法

### Kibanaダッシュボード

```
http://localhost:64297
ユーザー名: elastic
パスワード: (KIBANA_PASSWORD)
```

### Launcher Web UI

```
http://localhost:5000
```

### 現在のモード確認

```bash
curl http://localhost:5000/current-mode
```

## アンインストール

```bash
./uninstall.sh
```

アンインストール時、`data/`ディレクトリは自動的にバックアップされます：

```
${ARCHIVE_DATA_PATH}/Spring/${INSTALL_DATE}-${TODAY}-${TIME}/data/
```

## 設定カスタマイズ

### モードローテーション間隔の変更

[launcher/app/controllers/mode_controller.py](launcher/app/controllers/mode_controller.py)

```python
self.rotate_interval = 1020  # 秒（17分）
```

### モード順序の変更

[launcher/app/controllers/mode_controller.py](launcher/app/controllers/mode_controller.py)

```python
self.modes = ["sakura", "yozakura", "tsubomi"]
```

### ModeManager同期間隔の変更

[dispatcher/paramiko/src/mode/mode_manager.py](dispatcher/paramiko/src/mode/mode_manager.py)

```python
time.sleep(10)  # 秒
```

### セッションタイムアウト時間の変更

[launcher/app/controllers/session_manager.py](launcher/app/controllers/session_manager.py)

```python
SESSION_TIMEOUT = 300  # 秒
```

## 技術詳細

### ModeController（Launcher）

- シングルトンパターンで実装
- 初期モード: "sakura"
- 17分（1020秒）ごとに自動ローテーション
- モード切替時にコンテナの起動・停止を制御
- persist=Trueで常時起動、Falseでタイムアウト対象

### ModeManager（Paramiko）

- シングルトンパターンで実装
- 10秒ごとにLauncher API（`http://launcher:5000/current-mode`）をポーリング
- 初期化時とポーリング時にモードを同期
- `get_mode()`, `is_sakura()`, `is_yozakura()`, `is_tsubomi()` メソッドを提供

### OpenResty Mode Integration

- `worker_init.lua`: ワーカー起動時のモード初期化
- `log_mode_fallback.lua`: モード取得失敗時のフォールバック処理
- `detect.lua`: モード別の振り分けロジック

### Logstash

- 各ハニーポットの異なるログフォーマットを統一
- CSV（Heralding）、JSON（Cowrie/Wordpot/H0neytr4p）、カスタム（NGINX）を正規化
- `src_ip`, `src_port`, `dest_port`, `username`, `password`, `request_uri` などの共通フィールドへマッピング

## 関連プロジェクト

- **Sakura**: 動的多層型ハニーポットシステム
- **Yozakura**: 静的多層型ハニーポットシステム
- **Tsubomi**: ハニーポット単体運用
- **bloom-insight**: ログ分析・評価システム
