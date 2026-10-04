# 設計

判断をIOではなくGADTのプログラムにし、問い合わせへの答え方だけを差し替える。TS版と同じ画面とHTTP契約を保つ。基準は`../monster-battle-app`のcommit `14251cc`、背景は同リポジトリの`prompts/haskell-backend.md`と`docs/01`〜`06`。

## ライブラリと依存の向き

`domain ← decision ← sqlite ← http ← executable`をCabalの内部ライブラリで分ける。domainはbase・containers・textだけに依存し、HTTPやDBをimportできない。これは依存の境界であり、Haskellのbase自体からIOを取り除く仕組みではない。規則は純粋関数として書く。

`Decision e i j a`はReadingで読み、RefuseかSettleで判断を終える。GETはReadingで終わる型を要求し、Settle後はAsk・Refuse・Settleを続けられない。`QualifiedDo`を採用し、通常のIOのdoと同居させる。公開の判断用モジュールはGADTのコンストラクタを輸出しない。Internalはインタプリタと信頼済みユーザーを作る境界のためにCabal上は公開されており、パッケージ全体から不可視ではない。

共通の`Mba.Decision.Run`がPure・Bind・Refuse・Settleを解釈し、SQLite・モデル・デモは`Query a`への答え方を渡す。別々の完全なインタプリタを持たないため、操作の意味がずれにくい。変更はShow/Eqを持つデータ。PUTの冪等性は時刻を除いた状態で比較する。同じsaveを2回送ると変更は2回出るが、保存位置は同じ。帰宅のデモは2回目の変更を空にする。

RollとNewIdは未実装。追加時は能力の添字または同等の制約を導入し、GETで使用できず、個々の判断が必要な能力だけを持つ設計にする。Reading/Settledだけではこの制約を表せないため、追加前に設計と型の禁止例を更新する。

## 直列にする

1つのSQLite接続をMVarで囲む。GETも同じロックを取り、更新はBEGIN IMMEDIATEのトランザクション内で読み取り・判断・commitを行う。拒否時は書かない。接続内の途中状態は別リクエストに見せない。同時戦闘開始と同一ターンの並行要求の実証は戦闘の段階で行う。現在は複数プロセス構成を対象にしない。

## 境界と互換性

移植依頼書6節に対する方針を以下にまとめる。

| 項目 | 方針・現状 |
|---|---|
| 並行処理 | 上述のロックとトランザクション。並行要求のテストは今後 |
| 二言語の純粋関数 | TSから入力と期待出力を生成したJSONをコミットし、Haskellで読む。生成はNodeコンテナ、元コードには書き込まない。移動から開始し、矩形結合・合成・戦闘へ拡張 |
| 形と規則 | saveの整数はHTTPの形検査。管理の小数は規則でbad_stat等へ。検査順とmalformed.atをTSのテストと合わせる |
| JSON・文字列 | JSON値の等価性で比較。too_largeはJSのJSON.stringify相当のUTF-8サイズで判定する必要があり、aesonのencodeの長さで代用しない。名前はUTF-16単位とJSのtrimで処理。サイズ互換実装はスキン更新の段階 |
| 新しいID | 本番はMainでUUIDを生成し注入。テストは任意の固定ID。初期データの固定IDを保つ。現段階で新ID生成はない |
| 2つの上限 | readJsonが既知長・chunked両方のbody_too_largeを解析前に判定。too_largeは値を解析後に別判定 |
| 本番構成 | Node/GHCを含まない最終イメージ。uid 1000、0.0.0.0:3000、/app/data。Composeの独立したプロジェクト名とbashのHTTP healthcheck |
| 停止 | PID 1でSIGINT/SIGTERMを受け、Warpのlisten socketを閉じる。処理中要求の猶予は5秒。停止時間は実測して記録 |
| 数と乱数 | TSと同じ丸めと抽選順。テストの乱数1も許容。ターンはunknown_moveでも3つ消費、進行中戦闘の再取得は消費しない。戦闘段階でフィクスチャ化 |
| マイグレーション | コピーした9ファイルを名前順にDirect.execで実行し複数文をすべて適用。ファイルごとにトランザクション。通常の時刻はUnix秒、_migrations.applied_atはミリ秒 |
| 拒否順 | 管理APIは403→413→個別処理。置換PUTは存在確認が形より先、retireは形が先。管理段階でルート前の判定を実装 |

初期データは機能ごとに追加する。値はTSのseed/maps/authを基準とし、TS本番APIの応答による比較は今後の検証として扱う。まだ追加していないマスター・モンスターがある状態を「全初期データ一致」とは呼ばない。

マップ画面の段階では、`seed/player-default.json`に既定スキンの正本と描画用データを持つ。TSの固定commitから純粋なplayerSkin定義を取り出し、コピー済みのparseSkin/toRenderableで検証・変換して生成した資産であり、本番でNodeを実行しない。SQLiteのseedはこれを実際のskins行へ保存し、競合時は既存の編集・retire状態を維持する。ユーザーのスキン投稿を実装する段階で、Haskellの検証・描画変換を追加し、この正本を比較材料にも使う。

`GET /api/appearance`はAppearancesテーブルのレシピを型付きの問い合わせで取得し、未選択なら既定値を返す。GETで行を作らない。`GET /api/skins/:id`は保存済みの描画用JSONを再解析せず返す。retire済みでも取得できるのがTSの契約。現段階では見た目の更新・retire APIがなく、参照先のretireによるレシピの復帰・色の間引きは後続のretire段階で追加する。

## 環境の選択

既存のGHC 9.6.7、Cabal、WAI/Warp、小さなデータ駆動ルータ、aeson、sqlite-simple、Hspec/QuickCheck、fourmolu、hlintを継続する。過去の選定承認記録は残っていないため、現行実装を出発点にする。

コピーした5パッケージはfrontend内に置き、ルートのpnpm設定とlockfileを使って2 SPAの依存だけをインストールする。開発時もSPAをDockerでビルドし、publicからHaskellが配る。Viteの固定proxy設定を変更せず、1ポートの配信を開発時にも確認できる。本番イメージのwebステージだけにNodeを置く。

未実装のAPIを仮の固定応答で埋めず、各段階で実際のテーブル・判断・境界を通す。マップのexitsは移動段階まで空であり、この簡略化は全機能の完成までに解消する。
