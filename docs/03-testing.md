# 検証方針

下段はHspec/QuickCheckで純粋な規則・モデル上の判断・SQLite・WAI越しの契約を確認する。上段はTS版commit `14251cc`のE2Eを変更せず本番イメージへ向ける。通過した範囲と未実施の範囲を[ロードマップ](02-roadmap.md)に記録する。

```sh
docker compose run --rm --no-deps dev cabal test all --offline --test-show-details=direct
docker build --target check .
```

checkは警告をエラーとするビルド、テスト、fourmolu、hlintを含む。型の禁止例だけはそのファイルに限りfdefer-type-errorsを使い、実行すると段階・能力・検証済み型の型エラーになることを確認する。制約を緩める実験は一時コピーで行い、元の実装を汚さない。

QuickCheckは到達可能性、PUTの時刻を除く冪等性、同じ要求列のモデルとSQLiteの一致を検証する。変更を壊す実験では、その変更を守るテストが失敗することを確認する。新機能も例だけでなく関係する不変条件を追加する。

```sh
docker compose run --rm --no-deps --build lint fourmolu --mode inplace src app demo examples test
docker compose run --rm --no-deps lint hlint src app demo examples test
docker compose run --rm --no-deps dev sh scripts/check-mutations.sh
```

最後のコマンドはコンテナの一時コピーで9つを個別に変更する。確定後のAsk、確定後のNewId、GETのNewIdを許す3つの型制約の緩和と、水上歩行、保存レシピの無視、未使用色の許可、矩形の幅破壊、再直列化サイズ制限の無視、画面が表示するJSON項目順の破壊。各テストが実際に1件失敗した場合だけ成功とし、コンパイル失敗では代用しない。

## TSからの再生成

```sh
git -C ../monster-battle-app show 14251cc:apps/api/src/seed.ts > /tmp/monster-battle-reference-seed.ts
docker compose run --rm --no-deps --volume /tmp/monster-battle-reference-seed.ts:/reference-seed.ts:ro fixtures node scripts/generate-fixtures.mjs /reference-seed.ts
docker compose run --rm --no-deps fixtures node scripts/generate-sprite-fixtures.mjs
```

Node 24のコンテナで、コピー済みの純粋なTS関数を実行する。生成物は`seed/{player-default,skins}.json`と`test/fixtures/{movement,sprite}.json`で、コミットして通常のHaskellテストがネットワークなしで読めるようにする。移動は3種類のマップ、4方向、外周外の座標、離れた部屋を含む1,738ケース。テストではケース数も確認して空のフィクスチャによる誤成功を防ぐ。seedの生成はTSのparseSkinとtoRenderableを通す。スキン83件、レシピ30件、描画32件、合成12件、JSONサイズ216件と初期スキン4種を比較する。サイズは制御文字・絵文字・指数表記・有限Doubleの固定乱数列を含む。HTTPは生成フィクスチャの拒否結果に加え、201とLocation、保存正本と描画、2つのサイズ上限、所有者、retire後の読み取りを検証する。QuickCheckのスキン作成・着せ替え要求列は固定時計とID列で両インタプリタへ流し、各要求後の回答、保存された正本・描画・見た目、拒否の不変性、PUTの冪等性を比べる。これはTS本番API全体とのデータ比較を実施したという意味ではない。

## 現在の画面の受け入れ範囲

```sh
docker compose -f docker-compose.e2e.yml up -d --build --wait server
docker compose -f docker-compose.e2e.yml run --rm --build e2e pnpm exec playwright test tests/map.spec.ts tests/serving.spec.ts tests/editor.spec.ts tests/look.spec.ts --grep-invert 'answers every request a page makes'
docker compose -f docker-compose.e2e.yml down
```

mapの8件、servingの5件、editorの9件、lookの10件、計32件を対象にする。除外した配信テストは管理の種族・技・スキン一覧まで要求するため、管理API完成後に戻す。共有ユーザー・DBなのでworkersは1、複数のE2E実行を同じDBへ重ねない。失敗調査の成果物はコンテナ破棄前に確保する。

## 最終基準と未検証事項

```sh
docker build --target check .
docker compose -f docker-compose.e2e.yml up --build --exit-code-from e2e
docker compose -f docker-compose.e2e.yml down
```

全9 spec・64件で失敗0。既存の戦闘1件は乱数で1ターン決着するとskipする。HTTPの詳細は移植した契約テスト、純粋関数はTSからのフィクスチャ、初期データはTS本番応答と比較する。現段階で全E2E、並行戦闘、全初期データの一致、CI、性能比較は未実施。

最終段階でTS版と同一環境で3回ずつ時間を測り中央値を比較する。1割以内が目安であり、機能の完成とは区別する。SIGTERMによる停止時間も本番コンテナで実測する。
