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
- 仕様を勝手に変更しない

### Claude Cowork

- 独立した読み取り専用レビュー担当
- Codexと同じRepository `C:\src\keep_my_car` を参照する
- Repositoryの実ファイル読取、git diffと承認済み仕様の照合、実装・テストのread-onlyレビュー
- ファイル変更・自動修正・ファイル作成・削除・名称変更は禁止
- git add / commit / pushは禁止
- git reset / clean / checkout等、Repository状態を変更する操作は禁止
- 読み取り専用のgit status / diff / log等は許可
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
3. Codexが承認済み仕様をdocs/current_step.mdへ反映し、AGENTS.mdと承認済み仕様に従って実装・テスト（format / analyze / test / diff確認）
4. Claude Coworkがread-onlyレビュー
5. レビュー結果をChatGPT Project Chatで評価
6. 指摘を採用 / 却下 / 要検討に分類
7. 修正が必要ならCodexが修正
8. 必要に応じClaude Coworkが再レビュー
9. Review Outputの次工程移行条件に従い、PASS、またはChatGPT Project Chatと塁さんが指摘を確認し、Blockerではなく次工程を妨げないと判断したPASS WITH COMMENTSであることを確認
10. 塁さんがcommitを承認
11. Codexがcommit
12. working tree cleanを確認

Claude Coworkのレビュー結果を自動的に正式仕様とはしない。レビュー指摘の採否・設計判断はChatGPT Project Chatと塁さんが行う。

commit前確認・stageはAGENTS.mdと個別指示に従い、対象Stepの変更だけを扱う。読み取り限定・stage禁止・commit禁止等の個別指示を優先する。pushは明示承認がある場合のみ実施する。

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
git status --short
git diff --stat
```

Claude自身には修正、stage、commit、pushを行わせない。

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

必要なhistorical factは残してよいが、commit未実施・commit承認未取得・Flutter実装未承認・現在レビュー待ち・現在修正中など、すぐ陳腐化するcurrent-stateメタデータは原則として正式仕様本文に残さない。
