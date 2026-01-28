# Copilot Instructions – Spring

このプロジェクトでは、拡張性・堅牢性・保守性を最重視します。
Copilot は以下の方針・ルールに従ってコード提案を行ってください。
回答は原則日本語で行ってください。

---

## 基本方針

1. **既存機能を破壊しないこと（Backward Compatibility）**

- 機能追加や修正を行う際は、明示的な指示がない限り既存ロジックを残すこと。

2. **長期運用を前提とした堅牢性の確保**

- コネクション切断時は必ずリソース解放
- 不要データを保持する変数やバッファを残さない
- メモリリークの可能性がある箇所には try–finally を必ず適用

3. **単一責任原則（SRP）を守る**

- ロジックを混在させない。
- 例：
- SSH セッション管理は `core.py` に集約
- Flask ランチャーは起動・停止のみに責務を限定

---

## 言語ごとの規約

### Python

- 変数・関数名：**snake_case**
- クラス名：**PascalCase**
- コメントアウトは原則行わず、別途説明を加える
- 行末に書かず、必ず別行に書くこと
- Paramiko の client / shell / transport は **1 つのファイルにまとめて管理**
- `logging` モジュールを使用し、print は禁止
- finally によるクリーンアップを徹底

### JavaScript / TypeScript

- 変数・関数名：**camelCase**
- コメントは最小限

---

## Python の import 規則（統合ルール）

### **1. 並び順の基本原則**

- **最上段：`from x import ...`**
- **その下：`import x`**
- それぞれ **使用順に従って並べる**

---

### **2. 複数要素を from import する場合の統合ルール**

次をすべて満たすように書く：

#### **(a) 複数要素を import する場合も “使用順” に従って並べる**

```python
from module_x import b, a, c  # 使用順 b → a → c
```

#### \*\*(b) 使用順が異なる複数モジュール間の from 文は、

“最も早い段階で使用される要素” を含む from 文を上に置く\*\*

使用順が
**b（module_x） → func_y（module_y） → a（module_x） → c（module_x）**
の場合でも、最初に使用されるのは module_x の b であるため：

```python
from module_x import b, a, c
from module_y import func_y
import os
import sys
```

ポイント：

- module_x の「b」が最初に使用されるため module_x が最上位
- 次に module_y の「func_y」
- 複数関数をまとめた from 行内の並び順も使用順を尊重

このルールはすべての import に適用する。

---

### **3. 禁止事項**

- 使用順と無関係なランダムな import 順序
- 行末コメント
- 不要 import の残存
- from と import を混在させて基準なく配置

---

## SSH リバースプロキシに関する注意

- ターミナル挙動は **実際の Ubuntu のデフォルト設定に近づける**

- 履歴保持は 1000 件
- エコーやカーソル動作も実環境に合わせる
- Paramiko のリソースは必ず明示的に閉じる
- `client.close()`
- `transport.close()`
- `channel.close()`
- transport は paramiko.Transport(client)と client.get_transport()の双方

---

## コード構造の原則

- コアロジック（セッション管理・プロキシ処理）は分離して再利用可能にする
- Flask / Nginx などインフラ層と Python ロジックは疎結合に保つ
- 環境依存情報は config ファイルへ分離

---

## テスト・検証

- 例外処理のテストを必ず行う
- コネクション切断時にオブジェクトが残らないことを確認するテストを書くこと

---

## 出力フォーマット（Copilot への指示）

Copilot がコードを生成する際は以下に従う：

- 冗長なコードの生成を避ける
- 説明コメントは必要最低限にする
- Python：logging を使用する
- 型ヒント（type hints）は積極的に付与する
- 例外処理は必ず `try: ... except: ... finally:` の形で完結させる

---

以上のガイドラインに従うことで、Sakura プロジェクトの品質と保守性を高い水準で維持できます。
