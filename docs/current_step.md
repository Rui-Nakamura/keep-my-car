# Phase 05 Step 6 - Navigation & Screen Skeleton Baseline

## Status

Approved.

## Purpose

Step 5で完成したHomeを起点として、
通常利用時の主要画面構造と遷移を実機上で成立させる。
各画面の本機能はまだ作り込まず、アプリ全体の骨格を確認する。

## Normal-use Screens

1. Home
2. 未来タイムライン
3. 愛車予定費
4. 大型修理への備え
5. 計画設定

初回オンボーディングはこの5画面とは別フローとして後工程で扱う。

## Navigation Structure

HomeをHubとする。

```text
Home
├─ 未来タイムライン
├─ 愛車予定費
├─ 大型修理への備え
└─ 計画設定
```

BottomNavigationBar / NavigationRail / Drawer は使用しない。

子画面へはHomeから遷移し、
OS/Flutter標準の戻る操作でHomeへ戻る。

## Home Changes

### 未来の自分と愛車

「未来タイムラインを見る」という文字付き導線を追加する。
タップで未来タイムライン画面へ遷移する。

### 大型修理への備え

「詳しく見る」という文字付き導線を追加する。
タップで大型修理への備え画面へ遷移する。

### 予定費

現在の「予定費を追加」は、
「予定費を見る・追加する」へ変更する。

タップで愛車予定費画面へ遷移する。
Step 6では追加Formは開かない。

### 設定

既存の「設定」Navigation Rowを、
計画設定画面へのNavigationへ接続する。

## Screen Skeletons

### 1. 未来タイムライン

最低限以下を表示する。

- Page Title: 未来タイムライン
- 70歳までの計画
- 必要なら短い説明文
  「これからの予定費と愛車の未来を時系列で確認できます。」

Timeline本体は実装しない。

### 2. 愛車予定費

最低限以下を表示する。

- Page Title: 愛車予定費
- 6件の予定

Golden Sampleの予定件数を使用してよい。

以下はまだ実装しない。

- 予定費6件一覧
- 追加Form
- 編集
- 完了処理
- 削除

### 3. 大型修理への備え

最低限以下を表示する。

- Page Title: 大型修理への備え
- 200万円
- 65歳までに

Golden SampleのDomain Dataを画面外から渡す。

以下はまだ実装しない。

- 編集
- 積立進捗
- 安心判定
- Stress Test

### 4. 計画設定

以下のSection見出しを表示する。

- 愛車
- オーナー
- 保有目標
- 現在の愛車資金
- 普段の維持費
- バックアップ

Navigation Row風の見た目は可。
ただしStep 6では各項目の遷移・編集は実装しない。

## Common Child Screen UI

- Homeは現在のAppBarなし構成を維持
- 子画面はFlutter標準AppBarを使用してよい
- Scaffold
- 必要に応じてSafeArea
- 左右margin 20
- 縦方向へ伸長可能
- 横Scrollなし
- 既存Calm Planning UI Themeを使用
- Textを固定heightで押し込めない
- 標準Back Buttonを利用する
- 独自Navigation Barは作らない

## Navigation Implementation

Flutter標準の以下だけを使用する。

- Navigator.push
- MaterialPageRoute

以下は導入しない。

- go_router
- auto_route
- named route管理
- RouteGenerator
- DI
- State Management

HomeScreen自身が遷移先Screenを直接生成してよい。
専用Navigation Layerは作らない。

## Data Passing

Presentation層から
sample_data/golden_sample.dart へ直接依存しない。

必要な値だけをConstructorで渡す。

例:

- Planned Expenses: List<PlannedExpense>
- Repair Reserve: MajorRepairReserve

Skeleton表示のためだけに
ViewModel / State / Controller 等の新しい抽象化は作らない。

## Tests

最低限以下をWidget Testで確認する。

### Navigation

Homeから以下4画面へ遷移できる。

- 未来タイムライン
- 愛車予定費
- 大型修理への備え
- 計画設定

### Back

各子画面から戻るとHomeへ戻れる。

### Skeleton

各子画面のPage Titleが表示される。

### Home Regression

既存Homeの主要表示を維持する。

- 70歳まで
- あと13年7か月
- 月30,000円

### Responsive / Accessibility Test

360 logical px と文字倍率3.0の検証対象は、Home + 4子画面の全5画面とする。
最低限以下で例外・横Overflowがないこと。

- 360 logical px
- 文字倍率3.0

### Existing Tests

Step 6実装に必要な範囲でStep 5既存テストを更新してよい。
特にno-opを前提としたNavigation関連テストは、
Step 6の実際の画面遷移仕様に合わせて更新する。
ただしStep 5で確立した既存UI保証を不必要に削除しない。
既存Homeテストを不必要に書き直さず、Navigationテストを追加する。

## Out of Scope

Step 6では以下を実装しない。

- Timeline本体
- 予定費一覧完成版
- 予定費追加/編集Form
- 大型修理編集Form
- 設定編集画面
- Onboarding
- Empty / Overdue / Conflict等
- SQLite
- Repository Layer
- Planning Engine
- State Management
- go_router
- Bottom Navigation
- Deep Link
- 独自Animationの新規実装（MaterialPageRouteが提供する標準画面遷移Animationは許容する）
- 通知
- Cloud
- AI

## Acceptance Criteria

以下をすべて満たせばStep 6 PASS。

- HomeがHubとして機能する
- 4子画面へ実際に遷移できる
- 標準Back操作でHomeへ戻れる
- Bottom Navigationなし
- Flutter標準Navigatorのみ
- sample_dataへのPresentation直接依存を新たに作らない
- 4子画面はSkeletonに留まる
- Calm Planning UIを維持
- Step 5 Homeの主要Hierarchyを崩さない
- 360pxで横Overflowなし
- Dynamic Type 3倍で例外なし
- flutter analyze PASS
- flutter test PASS
- package追加なし

## Implementation Boundary

この文書更新時点では、まだStep 6のコード実装は行わない。
Codexはこの文書更新後、別途実装指示を受けるまで待機する。
