# Keep My Car - Development Workflow

## Roles

### ChatGPT Chat

- 企画
- 要件定義
- UI/UX検討
- Architecture判断
- Step仕様決定
- 最終判断の支援

### Local Work

- Repositoryの実ファイル読取
- git diffと仕様の照合
- Codex実装後のread-onlyコードレビュー
- 現在の環境ではRepositoryへの書き込みを前提としない

### Codex

- Repository内Markdownの作成・更新
- docs/current_step.mdへの承認済み仕様の反映
- 実装
- format / analyze / test / diff確認
- commit前確認
- 人間の明示承認後のcommit
- 仕様を勝手に変更しない

## Standard Flow

1. ChatGPT Chatで次Stepの仕様を検討
2. ユーザーが仕様を承認
3. Codexが承認済み仕様をdocs/current_step.mdへ反映
4. Local Workがdocs/current_step.mdをread-only確認
5. CodexがAGENTS.mdとdocs/current_step.mdを読んで実装
6. Codexがformat / analyze / test / diff確認
7. Local WorkがRepositoryをread-onlyレビュー
8. 必要ならCodexが修正
9. Local WorkがPASS判定
10. Codexがcommit前確認とstageを実施
11. ユーザーがcommitを承認
12. Codexがcommit
13. 次Stepへ

## Source of Truth

- 製品の長期前提: docs/product_baseline.md
- AI共通ルール: AGENTS.md
- 現在実装する承認済み仕様: docs/current_step.md
- コミット済み実装: Git HEAD
- 現在のレビュー対象: Git HEADとの差分、および未追跡ファイル
- チャット履歴だけを実装仕様の正本にしない
