# ロードマップ

2026-10-05。初期調査は[HANDOFF.md](../HANDOFF.md)。以下が継続作業で更新する現在地。

| 段階 | 状態 | 完了の基準 |
|---|---|---|
| 判断・マップ・保存 | 実装・検証済み | 型の禁止例、モデルとSQLiteの一致、HTTP |
| 文書・再現できるビルド | 完了 | README等、check、本番ビルド成功 |
| マップ画面 | 完了 | 既定スキン・見た目取得、移動フィクスチャ、マップ8件＋配信5件成功 |
| スキン編集・見た目更新 | 完了 | editor/look、矩形結合・合成の比較、ID能力と境界検証 |
| 管理・retire・移動 | 次、未実装 | admin/retire/travelと配信の残り1件 |
| 戦闘・成長 | 未実装 | battle/growth、並行処理、不変条件 |
| 最終検証 | 未実施 | 全機能のcheckと全64 E2E、初期データ比較、CI、処理中要求を含む停止。性能は別評価 |

## 今回の実装

スキン検証→描画変換→判断→モデル/SQLite→HTTPを追加した。見た目のレシピも境界で検証し、使用中のスキンと、合成後に実際に描かれる色を解決してから保存する。初期スキン4種の正本はTSから生成し、本番ではHaskellで検証・描画変換する。コピー済みのフロント・E2E・SQLとTS版の作業ツリーは変更していない。

| API | 今回の内容 |
|---|---|
| `POST /api/skins` | 新しいIDで保存、201とLocation。未知項目を除去、所有者はサーバが決定 |
| `GET /api/skins` | retire済みを除き、名前とmineを作成時刻・ID順で返す |
| `GET /api/skins/:id/source` | 編集用の正本。retire済みも取得可能 |
| `GET /api/skins/:id` | 保存時にHaskellで導いた描画用JSONを返す |
| `PUT /api/appearance` | 同じスキンのパーツ指定を省き、解決済みレシピ1行を置換 |
| `GET /api/appearance` | 未選択は既定値。retireされた本体・パーツ・色を返却時に復帰し、保存行は変更しない |

`Program c e i j a`にIDの能力を加え、GETと既存の更新は`WithoutIds`、作成だけ`WithIds`にした。実際のUUID取得はLinux Docker上のMainのみ。検証済みのSkinと参照解決済みのResolvedAppearanceを変更の入力型にする。何を防ぐか、外すと何が通るかは[設計](01-design.md)とREADMEに記載した。

JSONサイズはJSの再直列化に合わせる。UTF-16長、数値のDouble丸めと最短十進表記、制御文字の短いエスケープ、未知項目込みのサイズを比較した。スキン名はTSどおりtrimしない。

最初の対象E2Eでは30成功・2失敗だった。着せ替え画面が取得したレシピをJSON.stringifyして表示するため、JSON値の一致に加え項目順が必要だった。フロントを変えずAppearanceReplyのtoEncodingで順序を固定し、HTTPの回帰テストを追加した。

## 実行結果（2026-10-05）

| 検証 | 結果 |
|---|---|
| `docker build --target check .` | 修正後に成功。警告をエラーにするビルド、79 examples / 0 failures、fourmolu、hlint |
| 開発コンテナの`cabal test all --offline` | 79 examples / 0 failures。QuickCheck 4性質は各100試行 |
| TS移動フィクスチャ | 1,738件一致 |
| TSスプライトフィクスチャ | 検証83件、レシピ30件、描画32件、合成12件、JSONサイズ216件と初期スキン4種が一致 |
| `scripts/check-mutations.sh` | 型制約の緩和3件と機能破壊6件を、それぞれ対象テスト1件の失敗として検出 |
| 本番イメージの対象E2E | 修正後はmap 8件＋serving 5件＋editor 9件＋look 10件＝32 passed（19.7秒）、失敗・skipなし |
| コピー資産のバイト比較 | フロント5ディレクトリ・E2E・SQL計101ファイルがTS commit `14251cc`と一致 |

SPAビルドは既存キャッシュを利用した。フロントの単体テストを新たに実行したとは扱わない。全64 E2E、TS本番APIから取得した全初期データとの比較、戦闘の並行要求、処理中の停止、CI、性能比較は未実施。モデルとSQLiteの今回の要求列比較は固定時計を使い、時刻の異なるスキンの一覧順はHTTP/SQLの例で検証した。

検証用のE2Eコンテナは終了後に片付けた。初回の失敗調査用成果物は`/tmp/monster-battle-editor-failure`へ退避済み。

前段階（2026-10-04）は初回コミット`1d28c24`。Haskell 56件、マップ・配信E2E 13件が成功し、リクエストのない状態のSIGTERM停止を約0.52秒・終了コード0で確認済み。

## 次の着手点

管理→retire→マップ間移動へ進める。基準はTS版の`master.ts`、`retirement.ts`、`routes/admin.ts`と対応APIテスト。

1. 管理者の判定と技・種族の検証済み型、対応seed、管理の一覧・作成・置換を規則→判断→SQLite→HTTPで追加する。403→413→個別処理の拒否順を先に確認する。
2. マップ管理・出口と、参照を考慮したretire・復帰を追加する。物理削除しない。読み取り時の見た目復帰は今回実装済みで、状態設定をSQLから実際のretire APIへ広げて確認する。
3. 出口を通る移動を追加し、`admin.spec.ts`、`retire.spec.ts`、`travel.spec.ts`、残した`serving.spec.ts`1件を受け入れ範囲へ加える。travelの後片付けはretire APIに依存する。

マップのexitsは移動段階まで空。技・種族・所持モンスターのseedは未実装。戦闘・成長はその後に扱う。

## pushの状態

pushの依頼は受領済み。ただしremoteは未設定で、`gh repo view okayus/monster-battle-hs`でも参照できなかった。GitHub新規作成はAGENTS.mdにより明示依頼が必要なので、公開/非公開での作成、または別のpush先URLの回答待ち。送信先を推測してTS版へpushしない。
