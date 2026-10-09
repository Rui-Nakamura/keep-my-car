# Keep My Car - Development Workflow

## Roles

### 塁さん

- Product Owner
- 最終承認者
- commit実施可否の承認者

### ChatGPT Project Chat

- 共同企画・Product Manager・アーキテクト
- 仕様策定・設計判断
- Codex向け実装指示作成
- Claude Cowork向けレビュー指示作成
- Claude Coworkのレビュー結果の採否判断
- 次工程へ進むかの判断支援

### Codex

- Repositoryを書き換える実装担当
- Flutter実装・テスト
- Repository内ファイルの変更、承認済み仕様のdocs/current_step.mdへの反映
- 必要なGit差分作成、format / analyze / test / diff確認
- commit前確認と、許可された範囲のstage
- 塁さんの明示承認後のcommit
- 正式commit後の検査、安全確認を経たGitHubへの通常push、およびpush後の検証
- 仕様を勝手に変更しない

### Claude Cowork

- 独立した読み取り専用レビュー担当
- Codexと同じRepository `C:\src\keep_my_car` を参照する
- Repositoryの実ファイル読取、git diffと承認済み仕様の照合、実装・テストのread-onlyレビュー
- ファイル変更・自動修正・ファイル作成・削除・名称変更は禁止
- git add / commit / pushは禁止
- git merge / rebase / reset / restore / stash / clean / checkout等、Repository状態を変更する操作は禁止
- 読み取り専用のgit status / diff / log等は許可
- Git確認では可能な限り `git --no-optional-locks ...` または環境変数 `GIT_OPTIONAL_LOCKS=0` を使用し、Git indexの更新や `.git/index.lock` の残留などの副作用を防ぐ
- 原則として `git fetch` は実行しない。working treeを変更しなくてもremote-tracking refs、`FETCH_HEAD` 等の `.git` 内部状態を変更するため。remote上のbranch SHAが必要な場合は、可能であればlocalのremote-tracking refsを更新しない `git ls-remote` 等で照会するか、remote確認をCodexへ依頼する
- 問題を発見した場合も自分では修正せず、レビュー結果だけを返す

## Claude Cowork Project

- Project名：Keep My Car｜Read-only Review
- 接続フォルダ：`C:\src\keep_my_car`
- Claude側のProject Instructionsにread-onlyレビュー方針を常設する
- Claude Project Memoryは補助情報としてのみ使用する
- Claude Memoryの内容だけを根拠に仕様判断しない

## Standard Flow

原則として以下の順序とする。

1. ChatGPT Project Chatで仕様・設計を検討
2. 塁さんが仕様を承認
3. Codexが承認済み仕様をdocs/current_step.mdへ反映し、AGENTS.mdと承認済み仕様に従って実装／文書変更と必要な検査（実装時のformat / analyze / test、差分確認）
4. Claude Coworkがread-onlyレビュー
5. レビュー結果をChatGPT Project Chatで評価
6. 指摘を採用 / 却下 / 要検討に分類
7. 修正が必要ならCodexが修正
8. 必要に応じClaude Coworkが再レビュー
9. Review Outputの次工程移行条件に従い、PASS、またはChatGPT Project Chatと塁さんが指摘を確認し、Blockerではなく次工程を妨げないと判断したPASS WITH COMMENTSであることを確認
10. 塁さんがcommitを承認
11. Codexが対象Step／作業の明示されたファイルだけstageし、cached diffで承認対象との一致を確認
12. Codexがcommit
13. commit結果を検査し、HEAD・commit message・working tree clean等を確認
14. 下記のpush前必須確認を行い、問題がなければGitHub Private Repositoryへ通常のfast-forward push
15. push後必須確認を行い、local HEADとorigin/mainのSHA一致を確認

Claude Coworkのレビュー結果を自動的に正式仕様とはしない。レビュー指摘の採否・設計判断はChatGPT Project Chatと塁さんが行う。

commit前確認・stageはAGENTS.mdと個別指示に従う。`git add .` / `git add -A` は原則使用せず、想定外の差分があれば停止してProject Chatと塁さんへ報告する。読み取り限定・stage禁止・commit禁止・push禁止等の個別指示を優先する。

## GitHub運用

### 正式remoteとpushの原則

GitHub Private Repositoryを正式Git remote兼オフサイトバックアップとして扱う。ローカルPC故障時のコード・文書消失防止、正式な開発履歴のオフサイト保全、将来の別PC／Macへの移行、一人開発のバックアップリスク低減を目的とする。ただしGitHubを唯一のバックアップとはせず、Local Repositoryの保全も継続する。必要に応じた別媒体／別方式のバックアップとGit remoteでの保全は役割が異なる。

正式レビューと塁さんの承認を経て作成された正式commitは、commit後のRepository状態確認とpush前確認に問題がなければ、原則としてGitHubへpushする。「commit後もpushしない」を標準運用にはしない。ただしcommit成功を無条件のpush許可とは扱わない。commit、commit結果検査、push前確認、push、push後確認を別々に検証し、commit成功直後に未確認でpushしない。

通常はlocal branch `main`、remote `origin`、remote側branch `main`（追跡先 `origin/main`）を使用する。既存remote／upstream設定を勝手に変更しない。remote URL変更・別remote追加・branch変更・upstream変更には塁さんの明示承認が必要。

mainへpushするのは原則として正式レビュー・塁さん承認を経たcommitに限る。作業途中・未レビュー・未承認の変更を「バックアップ目的だから」という理由だけでmainへpushしない。現時点ではmainを基本とし、将来の作業branch導入時は別途運用を定義する。

### Push前必須確認

正式commit後、以下を確認する。

- branchが意図したbranchである
- HEADが今作成した正式commitで、commit messageが意図どおりである
- working tree、staged／unstaged／untrackedの状態に想定外の差分がない
- `.git/index.lock` がない
- remoteが意図したRepositoryであり、upstreamが意図どおりである
- 最新のremote側との履歴関係を確認し、通常のfast-forward pushが可能である

Codexが正式なpush前確認のために行うfetch等は許容するが、自動統合は禁止する。Claude Coworkのread-onlyレビューとは区別し、確認済みの対象だけを通常pushする。

### 停止条件とpush失敗時の対応

remoteがlocalより先行、local／remoteのdivergence、non-fast-forward、想定外のremote branch／URL、authentication／permission異常、その他の予期しないRepository状態ではpushを中止し、Project Chatと塁さんへ報告する。

Codexは勝手に `git pull`、`git pull --rebase`、rebase、merge、reset、force push、force-with-lease、remote履歴の書き換えを行わない。解決方針はProject Chatと塁さんが決定する。

通常運用では `git push --force` / `git push -f` / `git push --force-with-lease` を禁止し、GitHub上の正式履歴を書き換えない。例外には塁さんの個別の明示承認が必要。

pushが失敗しても正式commit自体を取り消さず、reset・commit作り直し・force pushを行わない。原因をProject Chatと塁さんへ報告し、判断を待つ。

### Push後必須確認

- local HEADとlocalの `origin/main` のSHAを確認し、一致していることを検証する
- さらに正式pushの最終確認として、可能な場合は `git ls-remote origin refs/heads/main` 等のread-onlyなremote照会を行い、GitHub上のmain SHAもlocal HEADと一致することを確認する。通常は `local HEAD = origin/main = GitHub remote main` の一致を確認する
- working tree、staged／unstaged／untrackedを確認する
- `.git/index.lock` がないことを確認する

remote照会時もcredentialやtokenを出力せず、認証情報入りremote URLを表示しない。照会失敗時はforce push等による修復を行わず、「確認不能」としてProject Chatと塁さんへ報告する。push自体の成功とremote照合結果を区別する。

pushコマンドの成功結果だけで完了扱いにしない。SHA不一致や予期しない状態があれば停止してProject Chatと塁さんへ報告する。

### 認証情報の扱い

token、credential、password、secret、GitHub認証情報をチャット・ログ・文書へ貼らない。remote情報の報告でも認証情報を含むURLを表示しない。secretが含まれる可能性のあるファイルをGit管理へ追加しない。

## Android実機検証

### 環境構成と担当

自宅から会社の開発PCへRDP接続する環境では、会社の開発PCにUSB接続された端末と、自宅の手元端末を区別する。

- Codex：会社の開発PCにUSB接続されたPixel 6aを使用した技術検証・APK操作を担当する。
- PO：自宅の手元スマートフォンを実際に操作するUX確認を担当する。
- Claude Cowork：READ-ONLY独立レビュー専用とする。APKインストール、Android実機への書込み・操作は禁止する。

### 通常の画面・機能・UX検証

会社Pixel 6a、自宅Pixel 6aはKeep My Carの検証専用端末とする。通常の画面表示・操作性・機能確認では、検証対象のKeep My Carをアンインストールし、新しいAPKをクリーンインストールする方法を標準とする。この2台では、通常検証時に古いKeep My Carのテストデータを削除してよいことをPOが承認済みとする。ただし、保存しておく必要があるデータが明示されている場合は、そのデータを勝手に削除しない。

### データ保持が目的の検証

Persistenceのデータ保持確認、既存データを保持したAPK更新、Export / Import、Backup / Recovery、スマートフォン間のデータ移行では、クリーンインストールを標準としない。検証目的に合うデータ保護方式を使用し、必要に応じて `adb install -r` による既存データ保持型更新を使用する。データ保持型の更新に失敗した場合は、アンインストールやデータ消去による回避を行わず、作業を停止してPOに報告する。

### 共通の安全ルール

- 対象端末と対象package名を確認する。
- 検証用APKのSHA-256を確認し、ビルド元のGit HEADと未commit変更を識別する。
- 同一端末への書込み操作は同時に1セッションのみとする。実際の競合操作がある場合、または排他性を確保できない場合は停止する。
- ADBサーバーやFlutter daemonが存在することだけを、書込み競合と判定しない。
- 他のアプリを削除しない。
- 別セッションによる想定外のAPK更新を検出した場合は受入を停止する。
- 通常のクリーンインストールでは、旧APKの署名一致・旧lastUpdateTimeの詳細照合を必須にしない。

## Review Output

問題を指摘する場合は、以下を記載する。

1. 対象ファイル
2. 該当箇所
3. 問題内容
4. なぜ問題なのか
5. 影響範囲
6. 推奨修正方法
7. 重要度

重要度：Critical / High / Medium / Low

総合判定：PASS / PASS WITH COMMENTS / FAIL

次工程移行条件：

- PASS：次工程へ進んでよい。
- PASS WITH COMMENTS：指摘内容をChatGPT Project Chatと塁さんが確認し、Blockerではなく次工程を妨げないと判断した場合は、次工程へ進んでよい。自動的にPASS扱いしてはならない。
- FAIL：修正および再レビューが完了し、上記の次工程移行条件を満たすまで、次工程へ進んではならない。

## 同一Repository利用時の安全確認

Claude Coworkは技術的にはローカルファイルを書き込めるため、read-onlyはプロジェクト運用上の厳格な制約として扱う。

Claudeレビュー前後で、必要に応じて以下を確認し、レビューによる意図しないRepository変更が発生していないことを確認する。

```sh
git --no-optional-locks status --short
git --no-optional-locks diff --stat
```

併せて `.git/index.lock` の有無を確認する。optional lock抑止だけで副作用が完全になくなると扱わず、レビュー前後の状態を照合する。Claude自身には修正、stage、commit、pushやlockファイルの削除等を行わせず、異常はProject Chatと塁さんへの報告だけを行わせる。

## Source of Truth

- 正式仕様・実装状態・履歴のSingle Source of Truth：Repository内文書・ソースコード・テスト・Git履歴
- 製品の長期前提：docs/product_baseline.md
- AI共通ルール：AGENTS.md
- 現在実装する承認済み仕様：docs/current_step.md
- コミット済み実装：Git HEAD
- 現在のレビュー対象：Git HEADとの差分、および未追跡ファイル
- チャット履歴やClaude Project Memoryだけを実装仕様の正本にしない

## 運用文書と履歴の扱い

現在および今後の標準運用にClaude Coworkを使用する。過去にChatGPT Work / Local Workを使用した事実やレビュー実施記録は、当時の記録として維持し、Git履歴も書き換えない。

必要なhistorical factは残してよいが、push待ち・未push・push済み・commit待ち／未実施・stage待ち・承認待ち／commit承認未取得・Flutter実装未承認・現在レビュー待ち・現在修正中など、すぐ陳腐化するcurrent-stateメタデータは原則として正式仕様本文に残さない。必要な場合は作業報告として扱い、長期維持する正式仕様と分離する。「正式commit後は原則pushする」等の長期運用ルールは本書に記載する。
