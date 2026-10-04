# ロードマップ

2026-10-04。初期調査は[HANDOFF.md](../HANDOFF.md)。以下は継続作業で更新する現在地。

| 段階 | 状態 | 完了の基準 |
|---|---|---|
| 判断・マップ・保存 | 実装・検証済み | 型の禁止例、モデルとSQLiteの一致、HTTP |
| 文書・再現できるビルド | 完了 | README等、check、本番ビルド成功 |
| マップ画面 | 完了 | 既定スキン・見た目取得、移動フィクスチャ、マップ8件＋配信5件成功 |
| スキン編集・見た目更新 | 次、未実装 | editor/look、矩形結合・合成の比較、ID能力と境界検証 |
| 管理・retire・移動 | 未実装 | admin/retire/travelと配信の残り1件 |
| 戦闘・成長 | 未実装 | battle/growth、並行処理、不変条件 |
| 最終検証 | 未実施 | 全機能のcheckと全64 E2E、初期データ比較、CI、処理中要求を含む停止。性能は別評価 |

## この継続作業

README、設計、検証方針、AGENTS/CLAUDEを追加した。README欠落に加え、既存コードの整形差分・hlintの2件の指摘、lintステージにCabal設定がなくGHC2021として解析されない問題を解消した。

`GET /api/appearance`と`GET /api/skins/:id`を判断→モデル/SQLite→HTTPに追加した。既定スキンはTSの固定commitから生成した正本と描画データをseedする。再起動で既存の絵・名前・retire状態を上書きしない。TS版の作業ツリーには書き込んでいない。

## 実行結果（2026-10-04）

| 検証 | 結果 |
|---|---|
| `docker build --target check .` | 成功。警告をエラーにするビルド、56 examples / 0 failures、fourmolu、hlint |
| 開発コンテナの`cabal test all --offline` | 56 examples / 0 failures。QuickCheck 3性質は各100試行 |
| TS移動フィクスチャ | step 248件＋到達可能性1,490件＝1,738件一致 |
| `scripts/check-mutations.sh` | 確定後のAsk、水上歩行、保存レシピ無視の3変更を、各1件のテスト失敗として検出 |
| 本番ビルド・起動 | 成功、healthcheck成功 |
| 本番イメージの対象E2E | マップ8件＋配信5件＝13 passed（3.8秒）、失敗・skipなし |
| SIGTERM停止 | リクエスト処理のない状態でCompose stopが約0.52秒、終了コード0、ログにstopped |
| コピー資産のバイト比較 | フロント5ディレクトリ・E2E・SQL計101ファイルがTS commit `14251cc`と一致 |

SPAビルドは既存キャッシュを利用した。フロントの単体テストを新たに実行したとは扱わない。全64 E2E、TS本番APIから取得した全初期データとの比較、戦闘の並行要求、処理中の停止、CI、性能比較は未実施。E2Eコンテナは終了後に片付け済み。

## 次の着手点

スキン編集→見た目更新の順で進める。基準はTS版の`skins.ts`、`appearance.ts`、それぞれのAPIテスト、`packages/sprite/src/index.ts`と単体テスト。以下を追加する。

- Haskellのスキン検証と描画変換。既定スキンの正本と、TSで生成する矩形結合フィクスチャで結果を比較する。
- 新ID取得の能力を判断に追加する前に、GETで取得できない制約と型の禁止例を設計する。
- `POST /api/skins`、一覧、正本取得、`PUT /api/appearance`。UTF-16長・JSのtrim・再直列化サイズ・検証順を合わせる。
- `editor.spec.ts`と`look.spec.ts`を、本番イメージの受け入れ範囲に追加する。

現状のAppearanceは保存レシピの読み取り用。更新時の検証済み型とスマートコンストラクタは次段階で導入する。retireされた参照先からのレシピ復帰と色の間引きはretire段階、マップのexitsは移動段階で実装する。
