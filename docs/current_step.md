# Phase 05 Step 7 - Planned Expenses List Baseline

日本語上の意味は「愛車予定費一覧の基本機能」とします。

## Status

Approved.

ただし、このApprovedは「Step 7仕様がProject Chatで承認済み」という意味です。

コード実装の開始承認ではありません。

---

## Purpose

Step 6で作成した「愛車予定費」画面に、Golden Sampleの予定費6件をread-onlyで表示する。

ユーザーが、

- いつ
- 何のために
- いくら

必要になるのかを把握できる一覧を作る。

さらに年単位で予定費をまとめ、その年に必要となる予定費の合計金額も表示する。

この画面は過去の支出履歴を見る車計簿ではなく、将来の愛車維持費を確認するための画面とする。

---

## Screen Information

画面上部はStep 6で確立した子画面構造を維持する。

- Flutter標準AppBar
- 標準Back Button
- Page Title「愛車予定費」
- 渡された予定費Listの実際の件数を「N件の予定」として補助表示（Golden Sampleでは「6件の予定」）
- 既存Calm Planning UI Themeを維持
- 左右margin 20を基本とする
- 横Scrollなし
- 縦方向へ安全にScroll可能

---

件数表示は `PlannedExpensesScreen` が受け取ったListの件数に連動する。20件なら「20件の予定」、空Listなら「0件の予定」とし、Golden Sample専用の固定文字列にしない。

本文中の「2027年 合計 190,000円」「タイヤ交換」「2028年6月」「200,000円」等は、画面構成や表示形式を説明するための例であり、Golden Sampleの実値を示すものではない。Golden Sampleの正本はRepository内の既存Golden Sampleとする。

## Planned Expense List

Golden Sampleの予定費6件を表示する。

「すべて表示」とは、縦Scrollを含めて全件を確認できることを意味し、6件すべてが同時に1画面内へ収まることは要求しない。将来20～30件へ増えた場合も同様とする。

予定費は予定年月の昇順で表示する。

例：

2027年
2028年
2029年

の順とする。

Golden Sample自体が偶然予定年月順に並んでいることには依存しない。

表示用に並べ替える場合、受け取った元のListを直接変更せず、コピーしたListを並べ替える。

---

## Same-Month Order

同じ予定年月の予定が複数存在する場合は、入力された順番を確実に維持する。

「入力順」とは、`PlannedExpensesScreen` が受け取った `List<PlannedExpense>` における元の並び順を意味する。

年月だけを比較した結果、同年月の予定が偶然元の順番になることには依存しない。

必要なら表示用コピーを作成する際に元の位置を保持し、第1比較を予定年月、第2比較を元の位置として順序を保証してよい。実装方法を固定するものではなく、同年月の入力順を確実に維持できる標準Dart/Flutterによる単純な別実装でもよい。

名称順、金額順などへ勝手に並べ替えない。

この順序保証のためだけにDomain Modelへの `sortOrder` 等の項目、新しいModel、Service、packageは追加しない。

---

## Year Grouping

予定費は年単位でグループ化する。

例：

2027年
  車検法定費用
  車検整備費用

2028年
  タイヤ交換

のような構造とする。

月単位のサブグループは作らない。

年グループ表示のためだけに、新しいDomain Modelは追加しない。

年グループ化は画面表示側の責務とする。

---

## Annual Total

各年の見出しには、その年に予定されている費用の合計を表示する。

例：

2027年    合計 190,000円

年合計はGolden SampleやDomain Modelへ保存しない。

その年に属する予定費の金額から画面表示時に算出する。

---

## Planned Expense Row

予定費1件には以下の3項目を表示する。

1. 項目名
2. 予定年月
3. 予定金額

基本イメージ：

タイヤ交換
2028年6月    200,000円

Visual Hierarchyとしては、

- 項目名：主要情報
- 金額：主要情報
- 予定年月：補助情報

とする。

---

## Information Not Shown

Step 7の予定費一覧では以下を表示しない。

- オーナー年齢
- 車齢
- 「あと○年○か月」
- 費用カテゴリ

これらを一覧へ詰め込みすぎない。

特にオーナー年齢、車齢、時間距離については、将来実装する「未来タイムライン」で扱う。

「愛車予定費」は具体的な「いつ・何に・いくら」を確認する画面とする。

---

## Visual Design

年単位の大きなCardは作らない。

予定費1件ごとの大きなCardも作らない。

基本構造は、

年見出し
↓
予定費Row
↓
予定費Row
↓
十分なVertical Spacing
↓
次の年

とする。

Row間には必要に応じてsubtle dividerまたは適切なSpacingを使用してよい。

年Group間はRow間より大きなVertical Spacingを確保する。

費用カテゴリによる色分けはしない。

特に警告色は、将来の資金不足、Overdue、Stress等の意味のある状態のために残す。

---

## Read-only

Step 7では予定費Rowをタップ可能にしない。

以下も付けない。

- Chevron
- Navigation affordance
- 編集画面へのNavigation
- no-opのTap処理

編集機能が存在しない段階で、押せそうなのに何も起こらないUIを作らない。

---

## Data Passing

Presentation層から sample_data/golden_sample.dart へ直接依存しない。

PlannedExpensesScreenは必要な予定費をConstructorで受け取る。

基本的には、

List<PlannedExpense>

を受け取る形とする。

概念的には、

Golden Sample
↓
上位のComposition部分
↓
List<PlannedExpense>
↓
PlannedExpensesScreen

とする。

将来Golden SampleをSQLite等へ置き換えても、PlannedExpensesScreenの責務を大きく変更しなくて済む構造を維持する。

Step 7のためだけに以下を導入しない。

- ViewModel
- Controller
- State Management
- Repository Layer
- DI

---

## Presentation Responsibility

以下は画面表示側の責務とする。

- 予定年月昇順への並べ替え
- 年単位のグループ化
- 年合計の算出
- 金額の表示形式への変換
- 年月の表示形式への変換

ただし過剰な抽象化は行わない。

---

## Amount Formatting

金額は日本向けMVPとして、

200,000円

のように表示する。

20万円のような概算表示ではなく、具体的な金額を表示する。

Step 7のためだけに以下は導入しない。

- Localization framework
- Money class
- Currency abstraction
- Formatter service
- intl等の新規package

ただし同じ金額表示処理をUIコードの各所へ不必要に散在させない。

---

## Date Formatting

予定年月は、

2028年6月

のように表示する。

Domain Dataそのものへ日本語表示文字列を保存しない。

表示時にPresentation側で変換する。

---

## Golden Sample

Repositoryに存在するGolden Sample 6件を正本としてそのまま使用する。

Step 7のUIを綺麗に見せる目的だけでGolden Sampleの予定年月、名称、金額等を変更しない。

Golden Sampleは今後、

- Home
- 愛車予定費
- 未来タイムライン
- 大型修理への備え
- 将来のPlanning Engine

等を横断して確認するための基準データとして扱う。

実装中にGolden Sampleそのものへ問題を発見した場合は、勝手に修正しない。

その場合は実装を止め、Project Chatで仕様判断を行う。

---

## Responsive / Accessibility

Step 6で確立した以下の検証をStep 7でも維持する。

- 360 logical px
- textScaler 3.0
- 横Overflowなし
- 例外なし
- 横Scrollなし
- Textを固定heightへ押し込めない

予定費一覧固有の条件として以下も守る。

### Long Name

長い予定費名称をellipsisで省略しない。

複数行へのwrapを許容する。

文字を自動縮小して押し込めない。

### Amount

金額をellipsisで省略しない。

横幅が足りない場合は必要に応じて縦方向へreflowする。

### Date and Amount

通常時は、

2028年6月    200,000円

のように同一行で表示してよい。

ただし狭い画面や大きな文字では、

2028年6月
200,000円

のように縦方向へ逃がしてよい。

同一行を強制しない。

### Year Header

通常時は、

2027年    合計 190,000円

のように表示してよい。

横幅不足時には、

2027年
合計 190,000円

のようなreflowを許容する。

固定heightを設定して押し込めない。

---

## Long-term List

Golden Sampleは6件だが、将来的には20～30件程度へ増えることを想定する。

縦方向へ安全にScrollできる構造とする。

ただしStep 7では以下を導入しない。

- Pagination
- Search
- Filter
- Sort切替UI
- Collapse / Expand
- Sticky Header

具体的にListView等のどのFlutter Widgetを使うかは仕様で固定しない。

既存構造との整合性を考え、標準Flutter Widgetによる最も単純な実装を選択してよい。

---

## Empty Fallback

Step 7の通常確認対象はGolden Sample 6件とする。

ただし空のListが渡された場合にcrashや例外を発生させない。

空Listが渡された場合は「予定はありません」を必ず表示する。これは任意ではなく、Step 7の最低限のfallbackとする。

これは完成版Empty Stateではない。

Step 7では以下を作らない。

- Empty State専用Illustration
- 追加CTA
- 「最初の予定を追加しましょう」等の完成版案内
- Empty専用Card
- アプリ全体としての空データ対応

Step 7のEmpty対応は、原則として `PlannedExpensesScreen` に空Listを渡した場合の安全な表示に限定する。既存Home等まで空List対応を広げない。

---

## Duplicate / Same-name Data

同じ名称の予定が複数存在しても表示する。

同じ予定年月の予定が複数存在しても表示する。

同じ年月・名称・金額の予定が複数存在しても、Presentation側で勝手に重複排除せず、すべて表示・合算対象とする。

名称をunique keyとして扱わない。

重複登録を許可するかどうかは将来の入力Validationで判断する。

Step 7ではDomain Validationを新規実装しない。

---

## Large Amount

少なくとも、

3,000,000円

程度の金額表示でレイアウトが破綻しないことを確認する。

Step 7では金額のDomain上の最大値は新たに定義しない。

---

## Tests

Step 7では既存Step 6のテスト保証を維持しつつ、予定費一覧固有のWidget Testを追加する。

最低限以下を確認する。

### Golden Sample

- 「6件の予定」が表示される
- Golden Sample 6件すべての項目名が表示される
- 予定年月が表示される
- 予定金額が表示される
- 金額が「200,000円」のような形式で表示される
- 予定年月昇順になっている
- 年単位でグループ化されている

Golden Sampleの具体的な6件の値をcurrent_step.mdへ二重管理する必要はない。

Repository内のGolden Sampleを正本とする。

### Annual Total

各年の表示合計が、その年に属する予定費の合計と一致すること。

Golden Sampleだけに依存せず、同一年の異なる月に複数予定があり、別年にも予定があるテスト専用データを使用する。

説明用のテストデータ例：

- 2027年4月：100,000円
- 2027年10月：50,000円
- 2028年6月：200,000円

期待値は2027年が150,000円、2028年が200,000円とし、年ごとに正しく合算・分離されることを確認する。このテストデータ例のために既存Golden Sampleを変更しない。

期待値は実装側の年合計処理を再利用して算出せず、テスト側で明確な期待値として確認する。

### Sort

Golden Sampleが偶然時系列順であることだけに依存しない。

テスト専用データとして、意図的に非時系列順の予定を渡し、画面上では予定年月昇順になることを確認する。

表示用の並べ替え後も、渡された元Listの順序・内容が変更されないことを確認する。既存sortテスト等に含めてよく、過剰な専用テスト構造は作らない。

### Same-Month Stable Order

同じ予定年月の複数予定を渡し、受け取った元Listでの並び順が確実に維持されることを確認する。

### Empty

`PlannedExpensesScreen` に空Listを渡しても例外にならず、「0件の予定」と「予定はありません」が表示されること。

### Duplicate / Same-name Data

同年月・同名・同額の予定が複数存在しても、1件へまとめず、すべて表示・合算対象となることを確認する。

### Long-term List / Count

テスト専用データ等で20～30件程度の予定を渡し、縦Scrollで末尾まで確認できること、横Scrollを導入していないこと、件数表示が渡されたListの実際の件数と一致することを確認する。

### Row Tap Review

Rowはread-onlyでタップ不可とする。このためだけの専用Widget Testは必須とせず、既存Widget構造および実装レビューで確認してよい。

### Responsive / Accessibility Worst Case

少なくとも1ケース、以下を同時に組み合わせる。

- 360 logical px
- textScaler 3.0
- 長い予定費名称
- 3,000,000円
- 年見出し
- 年合計

この状態で、

- 例外なし
- 横Overflowなし

を確認する。

文字の自動縮小やellipsisによって無理にPASSさせない。

---

## Existing Regression

Step 6で確立した以下を不必要に変更しない。

- Home
- Homeから4子画面へのNavigation
- 各子画面からHomeへ戻るBack操作
- 未来タイムラインSkeleton
- 大型修理への備えSkeleton
- 計画設定Skeleton
- Homeの主要Hierarchy
- 360 logical px / textScaler 3.0の既存保証

特にHomeの、

「予定費を見る・追加する」
↓
「愛車予定費」

のNavigationは引き続き機能すること。

---

## Development Note

Homeの導線は現在、

「予定費を見る・追加する」

となっているが、Step 7では追加Formをまだ実装しない。

開発途中の一時的不整合として、この文言はStep 7では変更しない。

「予定費を見る」へ一度戻し、追加機能実装時に再び変更する、といった往復変更は行わない。

ただし製品リリース時には、「追加する」と表示されているのに追加できない状態を残してはならない。

追加機能を実装するStepでこの不整合を解消する。

---

## Out of Scope

Step 7では以下を実装しない。

- 予定費追加Form
- 予定費編集Form
- 削除
- 完了処理
- CRUD
- SQLite
- Repository Layer
- State Management
- ViewModel
- Controller
- DI
- Planning Engine
- Timeline本体
- Search
- Filter
- Sort切替UI
- 年GroupのCollapse / Expand
- Sticky Header
- Pagination
- 完成版Empty State
- Overdue表示
- Conflict表示
- カテゴリ表示
- カテゴリ色分け
- オーナー年齢表示
- 車齢表示
- 「あと○年○か月」表示
- Row Tap
- Detail Screen
- 独自Navigation
- 新規package
- Localization framework
- Cloud
- AI

---

## Acceptance Criteria

以下をすべて満たせばStep 7 PASSとする。

1. 愛車予定費画面で縦Scrollを含めてGolden Sample 6件すべてを確認でき、件数表示が渡されたListの実際の件数に連動する
2. 予定年月昇順で表示される
3. 年単位でグループ化される
4. 各年の合計金額が正しく算出・表示される
5. 各予定に項目名・予定年月・予定金額が表示される
6. 金額は「200,000円」形式
7. 年月は「2027年4月」形式
8. 同年月では受け取った元Listの並び順を確実に維持し、元Listの順序・内容を変更しない
9. Golden SampleをPresentation都合で変更しない
10. PlannedExpensesScreenからGolden Sampleへ直接依存しない
11. 年合計等の表示用冗長データをDomainへ追加しない
12. Rowはread-onlyでタップ不可
13. PlannedExpensesScreenは0件でもcrashせず「0件の予定」と「予定はありません」を表示する
14. 長い項目名をellipsisせずwrapする
15. 金額をellipsisしない
16. 360 logical pxで横Overflowなし
17. textScaler 3.0で例外・横Overflowなし
18. 360 logical px + textScaler 3.0 + 長い名称 + 3,000,000円のworst-case testをPASSする
19. 20～30件程度でも縦方向へScrollして末尾まで確認可能
20. 横Scrollなし
21. Step 6のNavigation / Back / Home Regressionを維持する
22. flutter analyze PASS
23. flutter test PASS
24. package追加なし
25. SQLite / Repository / State Management等を先行導入しない

---

## Implementation Boundary

今回の作業は docs/current_step.md のStep 7仕様への更新までとする。

この文書更新とコード実装を同時に行わない。

docs/current_step.md更新後は、

1. 変更内容を自己確認する
2. git diff -- docs/current_step.md を確認する
3. Flutter/Dartコード、テストコード、pubspec等が変更されていないことを確認する
4. stageしない
5. commitしない
6. git pushしない
7. Local Workでread-only再確認できる状態で停止する

Step 7のFlutterコード実装は、Local Workレビュー結果をProject Chatで確認し、人間から別途明示的な実装開始指示を受けた後に行う。
