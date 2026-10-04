# 継続時の規約

元の依頼書は`../monster-battle-app/prompts/haskell-backend.md`。設計は`docs/01-design.md`、現在地と次の作業は`docs/02-roadmap.md`、検証は`docs/03-testing.md`を読む。

- 目的はHaskellで型と判断のインタプリタを学ぶこと。新機能、本物の認証、クラウド対応は追加しない。
- TS版は参照専用。コードと画面テストの基準はcommit `14251cc`。契約の細部はTS版のコード・APIテストを優先する。
- コピー済みの`frontend/apps/{web,admin}`、`frontend/packages/{core,sprite,sprite-react}`、`e2e/`、`migrations/*.sql`を変更しない。
- HTTPのパス・メソッド・ステータス・JSON・エラーの項目・拒否の順・Locationと初期データを合わせる。未知のパスと未対応メソッドは404。
- ホストに依存を導入しない。ビルド、検証、TSフィクスチャ生成はDockerで行う。既存のGHC 9.6.7、Cabal、WAI/Warp、aeson、sqlite-simple、QualifiedDo、Hspec/QuickCheck、fourmolu、hlintを継続する。これらの道具の変更はユーザーに相談する。
- 純粋な規則←判断←SQLite←HTTPの依存をCabalで守る。判断はIOを持たず、リクエストの書き込みはcommitだけ。エラーのステータスは1か所に集める。
- 乱数・時計・新しいIDは外から渡す。実際の取得はMainだけ。seedにも渡す。
- 境界で検証し、検証済みの内部型では同じ検査を繰り返さない。コンストラクタを隠す。判断を書く側はMba.Decisionのスマートコンストラクタを使う。
- ユーザーからSVG・画像・マークアップを受け取らない。数値と厳格な文字列からスキンを作る。DBに画像や合成済みの見た目を保存しない。物理削除せずretireする。
- 既存作品の名称・キャラクター名を持ち込まない。
- GHC2021、拡張は使用ファイルの先頭、明示的な輸出リスト、モジュール冒頭のHaddock。意味を与える関数はコンストラクタごとの等式で書く。unsafeCoerceやエフェクトライブラリを使わない。
- 規則→判断→SQLite→HTTP→対象E2Eの単位で進め、ロードマップへ実装済み・未検証・次の作業を分けて残す。型の仕掛けは、何を守り、外すと何が通るかを説明する。
- テストが対象の実装を壊すと失敗することを確認する。型の禁止例は制約を緩めると失敗することも確認する。
- mainへコミット。件名は英語のConventional Commits、本文は日本語の理由と「確認:」。pushとGitHubリポジトリ作成は依頼された場合のみ。

最終基準は`docker build --target check .`と、フィルタなしの`docker compose -f docker-compose.e2e.yml up --build --exit-code-from e2e`。E2E 64件は失敗0（既存の戦闘1件の条件付きskipは許容）。
