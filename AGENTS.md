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
- Claude Coworkによるファイル変更・自動修正・作成・削除・名称変更、およびgit add / commit / push / reset / clean / checkout等のRepository状態変更は禁止する
- Claude Coworkは読み取り専用のgit status / diff / log等で確認し、問題を発見しても修正せずレビュー結果だけを返す
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

- git status / diff / stage / staged diff確認は可
- stageする場合は、現在の対象Stepに属する変更だけをstageする
- 読み取り限定、またはgit add禁止の個別指示がある場合は、その指示を優先する
- git commitは塁さんの明示承認後のみ
- git pushは禁止。明示承認がある場合のみ実施する
