# monster-battle-hs 調査結果と実装引き継ぎ

## 継続作業後の現在地（2026-10-05）

スキン編集・保存・着せ替えまで実装・検証済み。新IDの能力添字、検証済みスキンと参照解決済みレシピ、4種の初期スキン、TS比較フィクスチャを追加した。`check`成功、Haskell 79件成功、破壊検証9件成功、本番E2Eはmap/servingの対象分とeditor/lookの計32件成功。コピー済みフロント・E2E・SQL計101ファイルはTS `14251cc`と同一。

**次は管理API・retire・マップ間移動。継続時は[AGENTS.md](AGENTS.md)、[現在のロードマップ](docs/02-roadmap.md)、[設計](docs/01-design.md)、[検証方針](docs/03-testing.md)を読む。** 全64 E2Eはまだ未実施。

着せ替え画面は受信JSONの項目順を文字列表示へ引き継ぐため、AppearanceReplyのtoEncodingでTSの順序を保っている。値の等価性だけに戻すとE2Eが2件失敗する。HTTPの回帰テストと破壊検証で固定した。

pushは依頼済みだがremote未設定。`okayus/monster-battle-hs`もGitHubで参照できず、新規作成の公開範囲、または別の送信先URLの回答待ち。詳細はロードマップ末尾。

以下は変更前の調査記録として残す。「README欠落」「46件」「未実装」の記述は調査当時の状態であり、現在地はロードマップを優先する。

---

調査日: 2026-10-04（Asia/Tokyo）

この文書は「現状を確認し、次を計画して」という依頼に対する調査と、その後の「別セッションで実装するためにMarkdownで共有する」という依頼をまとめたもの。実装担当は、まずこの文書と移植元の依頼書を読み、作業ツリーの変化を確認する。

**現在地: Haskellの判定基盤とマップ・セーブAPIは実装済み。既存Haskellテストは46件成功。本番イメージはREADME欠落でビルドに失敗し、E2Eでの完成確認には進めていない。**

このセッションではアプリのソースを変更していない。テストと本番イメージのビルドを実行し、最後に本ファイルを追加した。以下の計画は次セッション向けの提案であり、実装済みの事実とは区別する。

## 1. 目的と参照元

TypeScript版と同じアプリを、バックエンドだけHaskellに移植する学習用プロジェクト。ゲーム機能の追加ではなく、型で制約を表現し、判定をデータとして記述してインタプリタで実行する設計を学ぶことが目的。

| 対象 | 所在・基準 |
|---|---|
| 作業リポジトリ | `/home/okayu/indie-development/mazuoboeru-quizzes/monster-battle-hs` |
| 元の移植依頼書 | [../monster-battle-app/prompts/haskell-backend.md](../monster-battle-app/prompts/haskell-backend.md) |
| TS版リポジトリ | `/home/okayu/indie-development/mazuoboeru-quizzes/monster-battle-app`。参照専用 |
| コード・画面テストの基準 | TS版のcommit `14251cc` |
| 調査時のTS版HEAD | `6eef460`。直前の`c7f0971`とともに文書修正。文書は最新のローカル版を参照可能 |
| TS版の契約 | [docs/04-api-design.md](../monster-battle-app/docs/04-api-design.md)、`apps/api/src/*.test.ts`、`apps/api/src/refusals.ts` |
| データ・スキン・検証方針 | TS版の`docs/02-sprite-format.md`、`docs/03-data-model.md`、`docs/06-testing.md` |
| 設計の手本 | 元の依頼書が指定するmreactのcommit `f8a01f1`。今回の現状調査ではmreact自体は再調査していない |

元の依頼書が定める最終条件は以下。

- TS版のE2E 64件・9 specファイルを変更せず、本番イメージに対して失敗0にする。`battle.spec.ts`の1件には、乱数で1ターン決着した場合にskipする既存条件がある。
- HTTPのパス、メソッド、ステータス、JSON、エラーの`kind`と付随項目、`Location`を合わせる。
- 決まっている初期データのID・名前・数値・絵を合わせる。
- 1コンテナ・1ポートで`/`、`/admin`、`/admin/`、`/api`を提供する。

## 2. 実装済みの範囲

### 構成

依存の向きはCabalの内部ライブラリで分かれている。

```text
domain ← decision ← sqlite ← http ← executable
```

| 層・機能 | 主なファイル | 現状 |
|---|---|---|
| マップの純粋な規則 | [src/domain/Mba/Map.hs](src/domain/Mba/Map.hs) | タイル、座標、歩行、到達可能性 |
| 判定の言語 | [src/decision/Mba/Decision.hs](src/decision/Mba/Decision.hs)、`Decision/Internal.hs`、`Decision/Run.hs` | `Decision e i j a`、`Reading` / `Settled`、問い合わせと変更を表すGADT、共通インタプリタ |
| 純粋なモデル | [src/decision/Mba/Model.hs](src/decision/Mba/Model.hs) | マップ・セーブを値として保持し、判定と変更を適用 |
| マップ・保存の判定 | `src/decision/Mba/Maps.hs`、`Saves.hs` | 初期位置、無効なセーブからの復帰、同一マップ内で到達可能な位置への保存 |
| SQLite | [src/sqlite/Mba/Sqlite.hs](src/sqlite/Mba/Sqlite.hs) | マイグレーション、初期データの一部、問い合わせ、変更の書き込み |
| HTTP | [src/http/Mba/Http.hs](src/http/Mba/Http.hs)と`Http/`以下 | ルートをデータとして定義。JSON検証、本文サイズ制限、エラー変換、静的配信 |
| 起動 | [app/Main.hs](app/Main.hs) | 環境変数、DB準備、時計の注入、Warp、SIGINT/SIGTERM処理 |
| 学習用デモ | [demo/Demo.hs](demo/Demo.hs)、[examples/GoHome.hs](examples/GoHome.hs) | 読む→決める→変更→書くの表示。同じ保存の反復と、帰宅の2回目に変更が空になる例 |

判定で使える問い合わせは現在`FindMap`と`FindSave`、変更は`PlayerPlaced`。乱数や新しいIDを取得する操作はまだない。

SQLiteのリクエスト処理は同じ`MVar`で直列化される。更新は`withImmediateTransaction`内で判定と書き込みを行う。並行リクエストを送るテストまでは確認していない。

### 実装済みAPI

| メソッド | パス | 備考 |
|---|---|---|
| GET | `/api/health` | `status`と起動時の適用マイグレーション数 |
| GET | `/api/save` | 保存位置、または初期位置 |
| PUT | `/api/save` | 形、マップ、立てる位置、到達可能性を検証して保存 |
| GET | `/api/maps/:id` | 使用中のマップ。出口は現段階では常に空配列 |

その他のスキン、見た目、管理、retire、マップ間移動、所持モンスター、戦闘・成長のAPIは未実装。未知のAPIパスと未対応メソッドは404。

9本のSQLマイグレーションにより将来の機能のテーブルも作られるが、機能の実装が済んでいるという意味ではない。現在のseedはローカルユーザーと開始マップだけ。スキン・技・種族・所持モンスター等の初期データはこれから。

### TS版からコピー済みの資産

`git show 14251cc:<path>`の内容と、対応するローカルファイルをバイト比較した。下表の基準commitに存在するファイルは、すべて欠落・内容変更なし。

| TS版 | Haskell版 | 比較したファイル数 |
|---|---|---:|
| `apps/web` | `frontend/apps/web` | 39 |
| `apps/admin` | `frontend/apps/admin` | 21 |
| `packages/core` | `frontend/packages/core` | 7 |
| `packages/sprite` | `frontend/packages/sprite` | 4 |
| `packages/sprite-react` | `frontend/packages/sprite-react` | 5 |
| `e2e` | `e2e` | 16 |
| `packages/db/drizzle/*.sql` | `migrations/*.sql` | 9 |

この比較は上記の追跡済みファイルが対象。`frontend/`直下の共通設定や、コピー先だけに存在する追加ファイルの完全な監査は含まない。

## 3. 実行した検証と阻害要因

### Haskellテスト: 成功

プロジェクトルートで実行。

```sh
docker compose run --rm --no-deps dev cabal test all --offline --test-show-details=direct
```

結果:

```text
46 examples, 0 failures
Test suite spec: PASS
```

- マップ、モデル上の保存、HTTP、SQLiteを検証。
- 型エラーになるべき4ケースも成功。`test/TypeErrorSpec.hs`は、そのモジュールだけ`-fdefer-type-errors`を使っている。
- 到達可能性、PUTの冪等性、SQLiteとモデルの一致の3つのQuickCheckプロパティは、それぞれ100試行成功。
- 調査開始時のビルド成果物には古いFAILログがあったが、現在のコードでの再実行は成功した。現行の失敗として扱わない。
- 型制約を緩めてテストが落ちることを確認する作業は、今回は実施していない。

### 本番イメージのビルド: 失敗

```sh
docker compose --progress plain -f docker-compose.e2e.yml build server
```

失敗箇所は[Dockerfile](Dockerfile)の28行目。

```dockerfile
COPY --chown=dev:dev monster-battle-hs.cabal cabal.project cabal.project.freeze README.md ./
```

```text
"/README.md": not found
```

`README.md`が実在しない。`monster-battle-hs.cabal`の`extra-doc-files`にも参照がある。`check`ターゲットも同じ`source`ステージを使うため、この欠落を解消する必要がある。ただし今回`docker build --target check .`自体は実行していない。

SPAのビルドステージはこの実行ではキャッシュが使われた。フロントのクリーンビルドや単体テストを新たに実行した証拠とはしない。

### その他の状態

- 調査時点では`main`にコミットが1つもなく、ソース・設定はすべて未追跡。過去の変更差分はGitから復元できない。
- 本ファイル追加前には、プロジェクト内にREADME、設計文書、ロードマップ、`AGENTS.md`、`CLAUDE.md`がなかった。確認した親階層にも`AGENTS.md`はなかった。
- ソースには`docs/01-design.md`や`docs/03-testing.md`など、存在しない文書への参照がある。
- `.github/`はなく、CIは未整備。
- 開発用・E2E用のComposeプロジェクトは、状態確認時にコンテナなし。開発DBや`public/`などの生成物は既にあったため、クリーンな環境とはみなさない。
- E2E、ブラウザでの動作、SIGTERMでの停止所要時間、全体の整形・lint、TS版との性能比較は今回未検証。
- Dockerソケットへのアクセスはサンドボックス内では拒否され、実行権限を付けて検証した。これはアプリの不具合ではない。

## 4. 実装計画

以下の番号は今回の提案の順序であり、元の依頼書のStep番号ではない。既存実装を出発点とする。

### 1. 文書と再現可能な基準を整える

作業:

- 実装に即した`README.md`を作る。目的、依存関係、起動方法、型で防ぐ誤用、現在の未実装範囲を記載する。
- 日本語の設計・ロードマップ・検証方針を`docs/`へ記録し、ソース中の文書参照と整合させる。
- 元の依頼書の継続的な規約をリポジトリ内に残す。元文書は`CLAUDE.md`への転記を想定しているので、Codexを含む次の実行環境でも発見できる配置を検討する。
- README欠落を解消後、`check`と本番ビルドを実行し、追加の失敗があれば対応する。
- 現在のコードと検証結果を確認して初回コミットを作る。

完了条件: `check`・本番ビルド成功。文書に実装済み、未検証、次の作業が区別されている。型の仕掛けを説明できる。

既存資産: `Dockerfile`、Cabal設定、`test/`、元の移植依頼書。新しいビルド基盤は不要。

### 2. マップ画面をE2Eまで完成させる

作業:

- `player-default`のスキンと既定の見た目を、TS版と一致する形でseed・取得できるようにする。
- `GET /api/appearance`、`GET /api/skins/:id`を追加する。次段階で拡張できる実際のデータモデルで実装する。
- 既存マップ・セーブのHTTPテストをTS版と照合し、不足ケースを補う。別マップの拒否など、モデル上だけで確かめている条件にも注意する。
- TS/Haskell双方が持つ移動規則の比較用フィクスチャを用意する。
- `map.spec.ts`と、`serving.spec.ts`の先行可能な5件を実行する。

完了条件: `map.spec.ts`の8件、配信の5件、対象のHaskellテストが成功。

既存資産: `src/decision/Mba/{Maps,Saves}.hs`、`test/{Map,Saves,Http,Sqlite}Spec.hs`、`e2e/tests/map.spec.ts`。

### 3. スキン編集と着せ替え

作業:

- スキンの検証、描画用変換、保存・取得・一覧・編集用正本取得を実装する。
- 見た目レシピの検証・合成・更新を実装する。
- 新しいIDを判定に供給する仕組みを追加する。実ID生成は`Main`に置き、テストでは決め打ちにする。
- TSの`packages/sprite`から比較用フィクスチャを生成し、矩形結合・見た目合成等の出力をHaskellと比較する。
- UTF-16での長さ、trim、JSON再直列化後のサイズ判定など、言語差のある境界を契約に合わせる。

完了条件: `editor.spec.ts`・`look.spec.ts`成功。該当HTTP契約、検証順序、TS/Haskellの純粋関数の結果一致を確認。

既存資産: `frontend/packages/sprite/src/index.ts`とテスト、TS版の`skins.ts`・`appearance.ts`とAPIテスト、E2Eの2 spec。

### 4. 管理、retire、マップ間移動

この段階も、対象機能ごとに判定からHTTP・テストまで完了させる。

作業順序:

1. 管理者判定、技・種族・スキン一覧などの管理APIと対応seed。
2. マップ管理・出口データ。
3. 参照関係を考慮したretireと復帰。
4. 出口を通る移動。

完了条件: `admin.spec.ts`、`retire.spec.ts`、`travel.spec.ts`、`serving.spec.ts`全件成功。

注意: `travel.spec.ts`は後片付けにマップのretireを使う。管理APIでは403→413→個別処理という拒否順序も契約に含まれる。

既存資産: TS版の`master.ts`・`retirement.ts`・`routes/admin.ts`、各APIテスト、`e2e/tests/helpers.ts`。

### 5. 戦闘・成長と最終検証

作業:

- 所持モンスター、戦闘開始、ターン、勝利時の経験値、敗北時の回復と帰還を一緒に実装する。
- 乱数の取得を判定に追加し、乱数・ID・時計をテストから供給できるようにする。
- 同じターンを同時に送ったときの片方の`stale_turn`、同時戦闘開始の201/200と同一戦闘への収束を確かめる。
- 「1体につき進行中の戦闘は1つ」等の不変条件を、モデル上の要求列とSQLiteとの比較で検証する。
- 全E2E、ビルド・整形・lint、停止動作を確認する。CIは既存の検証コマンドを呼ぶ構成にする。
- TS版と同一環境で性能を比較する。元依頼書の目安は3回ずつの中央値で1割以内だが、性能は機能の完成条件とは別。差が大きければ理由を記録する。

完了条件: E2E 64件で失敗0（既存の条件付きskipは上記の通り）。HTTP契約・初期データの一致、同時実行時の整合性、CIの検証成功。

既存資産: TS版の`battles`・`growth`・`monsters`の実装とテスト、`frontend/packages/core/src/`、`battle.spec.ts`・`growth.spec.ts`。

## 5. E2Eの依存関係と実行方法

| spec | 順序を決める重要な依存 |
|---|---|
| `map` | セーブ、マップ、既定の見た目とスキン取得 |
| `serving` | 6件中5件は先行可能。`answers every request a page makes`はマップと管理画面が発行する全要求への応答が必要 |
| `editor` | スキン保存・取得・正本取得。マップ画面を開くケースもある |
| `look` | スキン作成・一覧・取得、見た目取得・更新 |
| `admin` | 管理API、マスターデータ、スキン保存・取得 |
| `retire` | 管理API、参照関係、見た目・セーブのフォールバック |
| `travel` | マップ管理、出口、移動、後片付け用のretire |
| `battle` / `growth` | 管理APIでの対戦環境作成、移動、retire、所持モンスター、戦闘と成長 |

`e2e/playwright.config.ts`は共有ユーザー・共有DBのため`workers: 1`、`fullyParallel: false`、`retries: 0`。同じDBを複数のE2E実行から操作しない。

本番ビルド修復後の、最初の対象E2Eの実行例:

```sh
docker compose -f docker-compose.e2e.yml up -d --build --wait server
docker compose -f docker-compose.e2e.yml run --rm --build e2e pnpm exec playwright test tests/map.spec.ts tests/serving.spec.ts --grep-invert 'answers every request a page makes'
docker compose -f docker-compose.e2e.yml down
```

この部分実行コマンドは引き継ぎ用の提案であり、今回実行したものではない。除外した配信テストは管理API実装後に戻し、最終確認はフィルタなしで実行する。失敗時の調査結果や成果物は、コンテナを破棄する前に確保する。

最終確認コマンド（元依頼書の完成基準）:

```sh
docker build --target check .
docker compose -f docker-compose.e2e.yml up --build --exit-code-from e2e
docker compose -f docker-compose.e2e.yml down
```

## 6. 継続時に守ること・決めること

元の依頼書に記載された方針:

- TS版の作業ツリーには書き込まない。コピー済みのフロント5ディレクトリ、`e2e/`、SQLマイグレーションの内容も維持する。
- 実装・テストの細かい契約はTS版のコードを優先する。ドキュメントと食い違った場合はコード側を確認する。
- 新機能、本物の認証、クラウド対応はスコープ外。
- ホストへの依存導入を増やさず、Docker内でビルド・検証・フィクスチャ生成を行う。
- 現在採用されている道具はGHC 9.6.7、Cabal、WAI/Warp、aeson、sqlite-simple、QualifiedDo、Hspec/QuickCheck、fourmolu、hlint。過去の選定承認の記録はこの調査では確認していないが、実装済みの選択を出発点にする。
- 判定はIOを持たず、リクエスト中の書き込みは`commit`に集める。ドメインの純粋性はCabalの依存で保つ。
- HTTP境界で検証した後は、内部型で規則を保持する。失敗を返す順番や`malformed.at`も契約として検証する。
- データは物理削除せず、retireする。
- 元依頼書のコミット方針は`main`へ、件名は英語のConventional Commits、本文は日本語で理由と「確認:」。pushとGitHubリポジトリ作成は依頼された場合のみ。

実装直前に詰める設計事項:

- `NewId`や`Roll`追加時、GETや個別判定に許す能力を型でどう制限するか。現行の`Reading` / `Settled`だけでは、読み取り中の乱数・ID取得までは制限できない。
- TSから作る比較用フィクスチャの生成方法と、生成物をコミットするかどうか。移動・描画変換・見た目合成で共通の手順を再利用する。
- JSONサイズ判定のJavaScript互換性と、初期データの比較方法。元依頼書の6節を読み、機能ごとに試験へ落とす。

## 7. 次セッションの最初の一手

1. `git status --short --branch`と本ファイルを確認し、調査後の変更を保護する。
2. 元の移植依頼書の3・4・6・8節を読み、現在の実装との差を把握する。
3. READMEと設計・進捗文書を作成する。本ファイルだけではDockerfileのREADME欠落は解消しない。
4. `docker build --target check .`と本番ビルドを確認し、実際の結果を進捗へ記録する。
5. 既定スキン・見た目取得を実装し、最初の受け入れ範囲であるマップ8件＋配信5件を通す。

以後は「規則→判定→SQLite→HTTP→対象E2E」の単位で完了させ、各段階の結果をロードマップに残す。新しい実行基盤を作る必要はなく、既存のテストとComposeを使う。
