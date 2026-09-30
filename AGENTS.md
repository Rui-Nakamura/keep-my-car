# Keep My Car - Agent Rules

## Project

- Flutter / Dart
- Android / iOS
- MVPは原則オフライン
- サーバ、ユーザーアカウント、クラウド同期はMVPでは勝手に追加しない
- 重要な金額・期間・積立額等は、将来のpure Dart deterministic Planning EngineをSingle Source of Truthとする
- AIに重要数値計算を担当させない

## Development Rules

- 役割分担・標準開発フローは docs/development_workflow.md に従う
- 塁さんがProduct Owner・最終承認者・commit実施可否の承認者を担う
- ChatGPT Project Chatが仕様策定・設計判断・レビュー指摘の採否判断を担い、CodexがRepositoryを書き換える実装担当を担う
- Claude CoworkはCodexと同じRepositoryを参照する独立した読み取り専用レビュー担当とする
- Claude Coworkによるファイル変更・自動修正・作成・削除・名称変更、およびgit add / commit / push / merge / rebase / reset / restore / stash / clean / checkout等のRepository状態変更は禁止する
- Claude Coworkは読み取り専用のgit status / diff / log等で確認し、問題を発見しても修正せずレビュー結果だけを返す
- Claude CoworkのGit確認は可能な限り `git --no-optional-locks ...` または `GIT_OPTIONAL_LOCKS=0` を使用し、index更新・index.lock残留等のレビューによる副作用を防ぐ
- Claude Coworkは原則 `git fetch` を実行しない。remote確認はlocalのremote-tracking refsを更新しない `git ls-remote` 等を優先するか、Codexへ依頼する。Codexの正式push前確認に必要なfetchは許容する
- Claude Coworkのレビュー結果を自動的に正式仕様とせず、ChatGPT Project Chatと塁さんが採否・設計判断を行う
- Claude Project Memoryは補助情報とし、正式仕様・実装状態・履歴はRepository内文書・ソースコード・テスト・Git履歴をSingle Source of Truthとする
- docs/current_step.md の承認済み仕様に従う
- 仕様にない機能を勝手に追加しない
- 曖昧さや矛盾があれば推測せず質問する
- 外部package追加は事前承認
- Theme変更は事前承認
- Android/iOS設定変更は事前承認
- application ID変更は禁止
- Golden Sample固有値をDomain Modelへ埋め込まない
- 普通の車計簿へ機能を広げない

## Validation

実装後は原則以下を実施する。

- dart format
- flutter analyze
- flutter test
- git diff --check

## Git

以下の変更操作の許可はCodexに適用する。Claude Coworkには上記の読み取り専用制約を常に適用する。

- git status / diff / staged diff等の確認は可。正式変更は必要な検査・read-only独立レビュー・塁さんの明示承認後に、対象Step／作業の明示されたファイルだけstageし、cached diffでcommit対象を確認する。`git add .` / `git add -A` は原則使用しない
- git commitは塁さんの明示承認後のみ。正式レビューと承認を経た正式commitは、commit後検査・push前確認に問題がなければ、原則としてGitHub Private Repositoryへ通常のfast-forward pushを行う
- 読み取り限定・stage禁止・commit禁止・push禁止等の個別指示を優先する
- 通常はlocal `main` → `origin` の `main`（追跡先 `origin/main`）を使用する。remote URL変更・別remote追加・branch変更・upstream変更は塁さんの明示承認なしに行わない
- commitとpushは別操作として検証する。push前にbranch、正式commitのHEADとmessage、working tree、staged／unstaged／untracked、`.git/index.lock`、remote、upstream、remoteとの履歴関係とfast-forward可否を確認する。remote確認のfetch等は可だが、自動統合は禁止する
- remote先行・divergence・non-fast-forward・想定外のremote branch／URL・認証／権限異常・想定外の差分やRepository状態では停止して報告する。勝手にpull（--rebase含む）／rebase／merge／reset／remote履歴書換えで解決しない。解決方針はProject Chatと塁さんが判断する
- `git push --force` / `git push -f` / `git push --force-with-lease` は通常運用で禁止する。正式履歴を書き換える例外には塁さんの個別の明示承認が必要
- push後はlocal HEADと `origin/main` のSHA一致、working tree、staged／unstaged／untracked、`.git/index.lock` を確認する。正式pushの最終確認では可能な限り `git ls-remote origin refs/heads/main` 等でGitHub上のmain SHAも照合する。照会できない場合は「確認不能」としてProject Chatと塁さんへ報告し、push自体の成功とremote照合結果を区別する。pushコマンドの成功だけで完了扱いにしない
- 作業途中・未レビュー・未承認の変更をバックアップ目的だけでmainへpushしない。作業branch導入時は別途運用を定義する
- push失敗時は正式commitを取り消さず、reset・commit作り直し・force pushを行わず、原因を報告してProject Chatと塁さんの判断を待つ
- token／credential／password／secret／GitHub認証情報をチャット・ログ・文書へ貼らない。remote報告で認証情報入りURLを表示せず、secretを含む可能性のあるファイルをGit管理へ追加しない
