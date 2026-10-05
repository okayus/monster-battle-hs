# 設計

判断をIOではなくGADTのプログラムにし、問い合わせへの答え方だけを差し替える。TS版と同じ画面とHTTP契約を保つ。基準は`../monster-battle-app`のcommit `14251cc`、背景は同リポジトリの`prompts/haskell-backend.md`と`docs/01`〜`06`。

## ライブラリと依存の向き

`domain ← codec ← decision ← sqlite ← http ← executable`をCabalの内部ライブラリで分ける。domainはbase・containers・textだけに依存し、HTTPやDBをimportできない。これは依存の境界であり、Haskellのbase自体からIOを取り除く仕組みではない。規則は純粋関数として書く。codecはaesonを使う境界とシリアライズをまとめる。判断のモデルとSQLiteの両方が同じ保存形式を使えて、HTTPへの逆依存を避けられる。

`Decision e i j a`はReadingで読み、RefuseかSettleで判断を終える。GETはReadingで終わる型を要求し、Settle後はAsk・Refuse・Settleを続けられない。`QualifiedDo`を採用し、通常のIOのdoと同居させる。公開の判断用モジュールはGADTのコンストラクタを輸出しない。Internalはインタプリタと信頼済みユーザーを作る境界のためにCabal上は公開されており、パッケージ全体から不可視ではない。

共通の`Mba.Decision.Run`がPure・Bind・Refuse・Settleを解釈し、SQLite・モデル・デモは`Query a`への答え方を渡す。別々の完全なインタプリタを持たないため、操作の意味がずれにくい。変更はShow/Eqを持つデータ。PUTの冪等性は時刻を除いた状態で比較する。同じsaveを2回送ると変更は2回出るが、保存位置は同じ。帰宅のデモは2回目の変更を空にする。

`Program c e i j a`は、能力`c`と段階`i/j`を独立に持つ。`Decision`は`WithoutIds`、`Creation`は`WithIds`の別名。`NewId`は`WithIds`かつReadingでしか使えない。GETのインタプリタは`WithoutIds`だけを受ける。単にReading→Readingに限定するだけではGETがIDを消費できるため、能力の添字が必要になる。`Run.create`は外から渡されたID取得作用を同じ共通インタプリタへ渡す。モデルでは凍結済み依存のtransformersのStateで有限ID列を消費し、未使用の列も返す。新しいエフェクトライブラリは導入していない。Rollは未実装。

## 直列にする

1つのSQLite接続をMVarで囲む。GETも同じロックを取り、更新はBEGIN IMMEDIATEのトランザクション内で読み取り・判断・commitを行う。拒否時は書かない。接続内の途中状態は別リクエストに見せない。同時戦闘開始と同一ターンの並行要求の実証は戦闘の段階で行う。現在は複数プロセス構成を対象にしない。

## 境界と互換性

移植依頼書6節に対する方針を以下にまとめる。

| 項目 | 方針・現状 |
|---|---|
| 並行処理 | 上述のロックとトランザクション。並行要求のテストは今後 |
| 二言語の純粋関数 | TSから入力と期待出力を生成したJSONをコミットし、Haskellで読む。生成はNodeコンテナ、元コードには書き込まない。移動・スキン検証・矩形結合・合成・JSONサイズを比較済み。戦闘は今後 |
| 形と規則 | saveの整数はHTTPの形検査。管理の小数は規則でbad_stat等へ。検査順とmalformed.atをTSのテストと合わせる |
| JSON・文字列 | 原則はJSON値の等価性で比較。ただし見た目レシピは未変更の画面がJSON.stringifyして表示するため、AppearanceReplyのtoEncodingでskinId→parts→colours、色のid→hex、パーツの描画順も保持する。too_largeはJSのJSON.stringify相当のUTF-8サイズで判定。未知の項目も含め、数値はDoubleへ丸めて最短の往復可能な十進表記を求める。1e23等の丸め境界も比較する。スキン名の長さはUTF-16単位で、TSどおりtrimしない。save等で必要なtrimとは分ける |
| 新しいID | 本番はMainがLinuxの/proc/sys/kernel/random/uuidを読み、末尾改行を除く。対象は既存のLinux Docker環境。判断は取得方法を知らず、テストでは任意の固定ID列を注入。初期スキンの固定IDを保つ |
| 2つの上限 | readJsonが既知長・chunked両方のbody_too_largeを解析前に判定。too_largeは値を解析後に別判定 |
| 本番構成 | Node/GHCを含まない最終イメージ。uid 1000、0.0.0.0:3000、/app/data。Composeの独立したプロジェクト名とbashのHTTP healthcheck |
| 停止 | PID 1でSIGINT/SIGTERMを受け、Warpのlisten socketを閉じる。処理中要求の猶予は5秒。停止時間は実測して記録 |
| 数と乱数 | TSと同じ丸めと抽選順。テストの乱数1も許容。ターンはunknown_moveでも3つ消費、進行中戦闘の再取得は消費しない。戦闘段階でフィクスチャ化 |
| マイグレーション | コピーした9ファイルを名前順にDirect.execで実行し複数文をすべて適用。ファイルごとにトランザクション。通常の時刻はUnix秒、_migrations.applied_atはミリ秒 |
| 拒否順 | 管理APIは403→413→個別処理。置換PUTは存在確認が形より先、retireは形が先。管理段階でルート前の判定を実装 |

初期データは機能ごとに追加する。値はTSのseed/maps/authを基準とし、TS本番APIの応答による比較は今後の検証として扱う。まだ追加していないマスター・モンスターがある状態を「全初期データ一致」とは呼ばない。

スキン4種の正本とTSの描画結果を`seed/skins.json`に持つ。固定commitのseed定義とコピー済みの純粋なTS関数から生成し、本番でNodeを実行しない。SQLiteのseedは正本をHaskellで検証して矩形結合する。併記したTSの描画結果はテストの期待値として使う。競合時は既存の編集・retire状態を維持する。従来の`seed/player-default.json`も比較用に残す。

`Skin`と`ParsedAppearance`のコンストラクタは境界用のInternalに隠す。スキンはパレット、5スロット、1〜8フレーム、セル数とインデックスを検証済みなので描画変換で再検査しない。`chooseLook`は使用中のスキンを読み、合成後に実際に描かれる色だけを許す。ここで得る`ResolvedAppearance`だけが`LookChosen`に渡せる。DBにはパーツと色のレシピを保存し、合成後の絵は保存しない。

`GET /api/appearance`は未選択なら既定値を返す。選択済みの参照先がretireされていれば、本体は既定値へ戻し、パーツだけなら該当パーツと不要な色を返却値から除く。保存行は変更せず、復帰後は元の選択が戻る。retireの書き込みAPI自体は次段階。`GET /api/skins/:id`と`/source`は保存済みJSONをそのまま返し、retire済みでも取得できる。一覧はcreated_at、id順で、retire済みを除き、所有者IDを出さずmineを返す。モデルの現在の比較は固定時計による同時刻データを対象とする。

## 環境の選択

既存のGHC 9.6.7、Cabal、WAI/Warp、小さなデータ駆動ルータ、aeson、sqlite-simple、Hspec/QuickCheck、fourmolu、hlintを継続する。過去の選定承認記録は残っていないため、現行実装を出発点にする。

コピーした5パッケージはfrontend内に置き、ルートのpnpm設定とlockfileを使って2 SPAの依存だけをインストールする。開発時もSPAをDockerでビルドし、publicからHaskellが配る。Viteの固定proxy設定を変更せず、1ポートの配信を開発時にも確認できる。本番イメージのwebステージだけにNodeを置く。

未実装のAPIを仮の固定応答で埋めず、各段階で実際のテーブル・判断・境界を通す。マップのexitsは移動段階まで空であり、この簡略化は全機能の完成までに解消する。
