# Keep My Car - Agent Rules

## Project

- Flutter / Dart
- Android / iOS
- MVPは原則オフライン
- サーバ、ユーザーアカウント、クラウド同期はMVPでは勝手に追加しない
- 重要な金額・期間・積立額等は、将来のpure Dart deterministic Planning EngineをSingle Source of Truthとする
- AIに重要数値計算を担当させない

## Development Rules

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

- git status / diff / stage / staged diff確認は可
- stageする場合は、現在の対象Stepに属する変更だけをstageする
- 読み取り限定、またはgit add禁止の個別指示がある場合は、その指示を優先する
- git commitは人間の明示承認後のみ
- git pushは禁止。明示承認がある場合のみ実施する
