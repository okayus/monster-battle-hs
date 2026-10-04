# monster-battle-hs

判断をデータとして書き、型で操作の順序を守り、インタプリタで実行するHaskellの学習用Webアプリです。

TypeScript版のバックエンドを移植しています。画面・画面テスト・SQLは[移植元](../monster-battle-app)のcommit `14251cc`をそのまま使用します。現在はマップ画面（移動・保存・既定の見た目）まで実装・検証済みです。全体の完成状況と実行結果は[ロードマップ](docs/02-roadmap.md)を参照してください。

## 実行

必要なのはDockerとComposeです。GHCやNodeをホストにインストールしません。

```sh
docker compose run --rm dev cabal update
docker compose run --rm dev cabal test all --test-show-details=direct
docker compose run --rm dev cabal run demo
docker build --target spa --output public .
docker compose run --rm --service-ports dev cabal run monster-battle-hs
```

プレイヤー画面は`http://localhost:3300/`、管理画面は`http://localhost:3300/admin`です。未実装APIを使う画面はまだ動作しません。開発DBは`data/dev.db`、Cabalの依存はDocker volumeに保存します。`PORT`の既定値は3000、`DATABASE_PATH`の既定値は`./data/app.db`です。

```sh
docker build --target check .
docker compose -f docker-compose.e2e.yml up --build --exit-code-from e2e
docker compose -f docker-compose.e2e.yml down
```

最後のE2Eコマンドは最終完成時の基準です。現在の対象だけを実行する方法は[検証方針](docs/03-testing.md)に記載しています。本番は1コンテナ・1ポートでAPIと2つのSPAを配信します。

## 型が守ること

`perform = commit ∘ decide ∘ read`。読み取りは判断の中の問い合わせで起き、変更をSQLにするのは`commit`だけです。同じ判断をSQLite、純粋なモデル、印字するデモで実行します。

| 操作 | 入力の添字 → 出力の添字 | 意味 |
|---|---|---|
| `pure` | `i → i` | 値を返す |
| `ask` | `Reading → Reading` | 型付きの問い合わせ |
| `refuse` | `Reading → j` | 断って以後を実行しない |
| `settle` | `Reading → Settled` | 変更の一覧を確定する |
| `>>=` | `i → j`と`j → k`を`i → k`へ | 操作をつなぐ |

次は型エラーです。確定後の読み取り、二度の確定、確定後の拒否、GETからの変更は実行前に止まります。

```haskell
bad user = D.do
  D.settle [PlayerPlaced user home]
  D.ask (FindSave user) -- SettledからReadingには戻れない

badGet :: Decision Refusal 'Reading 'Reading ()
badGet = D.settle [] -- GETが要求するReadingで終わらない
```

この制約を外すと、変更前のDBを確定後に再読したり、GETから更新したりできてしまいます。`test/TypeErrorSpec.hs`が4種類の禁止例を検証します。乱数とID取得の命令、バトルの段階を表す型は今後の実装です。

## モジュール

| 場所 | 役割 |
|---|---|
| `src/domain/Mba/Map.hs` | タイル、移動、到達可能性の純粋な規則 |
| `src/domain/Mba/Appearance.hs` | 保存された見た目のレシピと既定値 |
| `src/decision/Mba/Decision*` | 判断の言語、スマートコンストラクタ、共通インタプリタ |
| `src/decision/Mba/Model.hs` | メモリ上の状態と問い合わせ・変更の解釈 |
| `src/decision/Mba/{Maps,Saves}.hs` | マップと保存の判断 |
| `src/decision/Mba/Looks.hs` | 見た目レシピと保存済みの絵の取得 |
| `src/sqlite/Mba/Sqlite.hs` | マイグレーション、seed、直列化、SQLiteへの問い合わせとcommit |
| `src/http/Mba/Http*` | ルート、JSON境界、拒否、静的配信 |
| `app/Main.hs` | 時計・環境変数・起動と停止 |
| `demo/`、`examples/` | 判断を段階ごとに見せる例 |

設計判断は[設計](docs/01-design.md)、継続時の規約は[AGENTS.md](AGENTS.md)、最初の調査記録は[HANDOFF.md](HANDOFF.md)にあります。
