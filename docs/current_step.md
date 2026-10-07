# Phase 05 Step 15 — MVP情報設計・機能優先順位再整理

Status：Step 15-A 影響調査完了・Step 15方針確定。Step 15-B 計算の土台実装済み。Step 15-C Home Specification v0.3.1を承認済み仕様とする。

## Step 15の正式方針と過去仕様との関係

本節はProject Chatで承認されたStep 15の長期的な仕様・判断を記録する。実装済みのStep 15-Bについては下記の実装記録を参照し、それ以外の仕様記載を画面・計算の実装完了と扱わない。Step 15-C〜Fでは以下の方針に従って順に実装を進める。

過去のStep 8〜14は、当時の正式な仕様・判断・実装記録として維持する。本書後半のStep 11〜14の記録と、そこで参照しているStep 8〜10のGit履歴は削除・改変しない。Step 15で変更した事項は、本節をStep 15以降の正式方針として優先する。それ以外の既存仕様・保存安全性は継承する。

| 対象 | 過去の方針・既存仕様 | Step 15以降の方針・再確認 |
|---|---|---|
| Future Timelineの表示期間 | 基準年を含む10年間固定。保有目標で延長・短縮しない（Step 11 §24で継承） | 原則として保有目標まで表示する |
| Homeの情報 | 旧Homeの残り期間・目標時点の車齢・走行距離を戻さない（Step 11 §24／§29） | 新Homeでは保有目標とともに残り期間・目標時点の車齢・想定走行距離を表示する |
| 大型修理への備え | MVP中核として維持する（Step 13「初回MVPの中核と製品価値」） | MVPの主役から外す。既存の保存データ・計算・画面を直ちに削除しない |
| 月額準備額・積立額 | 毎月いくら準備するかを中心価値とする（Step 13「初回MVPの中核と製品価値」） | 予定費の時期・金額と自分・愛車の未来を中心にし、月換算は必要なら参考情報へ下げる |
| 期限超過予定費（既存仕様の再確認） | Step 8／9／11の既存仕様どおり、基準月より前の予定費は試算対象外・データは保持 | Step 15でもこの扱いを維持。現在月への自動繰越は行わない。過去仕様の上書きではない |
| Step 15の工程 | Step 13のロードマップではUI/UX販売品質改善として整理 | 情報設計・機能優先順位を本節で再整理し、計算の土台からHome・Timeline・補助機能・製品版UI/UXの順に進める |

Step 14に記録した0円表示・一定月額積立方式・大型修理予備費とTimelineの関係等の改善候補は当時の判断として残す。本節によってそれらの新機能実装を確定しない。Step 13のStep 16〜18のロードマップは維持する。

## 中心価値とMVPの優先順位

Keep My Carは、**好きな車を自分の保有目標まで乗り続ける場合に、いつ・どのくらいのお金が必要になりそうかを、自分の年齢・車齢・走行距離とともに見通すアプリ**とする。

「毎月いくら積み立てるか」や「大型修理への備え」を中心とした見せ方から重心を移す。製品コンセプト「好きな車に、あと何年乗れる？」は維持する。ただし、何年乗れるかを保証せず、故障時期を予測せず、故障確率を出さず、維持可能／不可能を断定しない。

| 優先順位 | 内容 |
|---|---|
| 主役 | 保有目標、愛車予定費、保有目標までの予定費合計、Future Timeline、Owner年齢、車齢、想定走行距離、次の予定費、近い将来の予定費見通し |
| 補助 | 費用が大きい年、月換算の参考値 |
| MVP後 | 大型修理ストレステスト、修理して維持 vs 買替え、高度な繰り返し登録、走行距離連動型予定費、年間予算／負担上限判定、物価上昇補正、車種別整備予測、AIによる故障予測 |

MVP後の一覧はStep 15時点では実装承認を意味しない。AIによる故障予測もMVPへ追加せず、故障時期・確率を出さない原則は維持する。将来候補を実装する場合の採否・原則との整合は別途判断する。

## Step 15-B：計算の土台（実装記録・継承）

正式checkpointは `b2761e594a1347f1c18bc856ba43a53f87d51b89`（`feat: build Step 15 plan summary foundation`）とする。保有目標年月に基づく要約getterと、保有目標までのFuture Timelineの土台を実装した。Home新設計の実装完了を意味しない。

Step 15-Cでは `PlanSession` の既存getterを再利用する。

- 保有目標：`ownershipTargetMonth`、`ownershipTargetOwnerAge`、`ownershipTargetCarAge`、`ownershipTargetMileageKm`
- 予定費：保存済み全件の `plannedExpenses`、試算対象の `includedExpenses`、`ownershipTargetExpensesTotalYen`
- 次の予定費：`nextExpenseMonth`、`expensesInNextMonth`、`nextMonthTotalYen`
- 近い将来：`nextYearExpensesTotalYen`、`fiveYearExpensesTotalYen`

## Step 15-C：Home新設計 — Home Specification v0.3.1

### 目的・情報階層

Homeは**「この車をいつまで乗るつもりで、その間にどんな支出が控えているかを、起動直後に把握する画面」**とする。予定費管理画面、積立管理画面、大型修理管理画面、単なるメニュー画面にはしない。製品コンセプト**「好きな車に、あと何年乗れる？」**を維持する。

通常状態では原則として上から次の順序とする。

1. 愛車名・設定
2. 保有目標
3. 保有目標までの登録済み予定費
4. 次の予定費
5. 近い将来の予定費
6. 未来タイムライン
7. 予定費追加

Homeで最も強く表示する情報は**「70歳まで乗る計画」**のような保有目標とし、予定費総額を最大の要素にはしない。本節の車名・年齢・金額・年月・走行距離の例は表示イメージであり、固定値やGolden Sampleの変更を意味しない。

### 保有目標と補助情報

通常状態では、保有目標に加えて残り期間、保有目標時の車齢、保有目標時の想定走行距離を表示する。

| 残期間・状態 | 表示 |
|---|---|
| 13年7か月 | あと13年7か月 |
| 7か月 | あと7か月 |
| 10年0か月 | あと10年 |
| 0か月（基準年月と保有目標年月が同じ） | 今月が保有目標です |
| 基準年月が保有目標年月より後 | 保有目標に到達しています |

残期間をWidget内で独自計算しない。実装時には `PlanSession` に保有目標到達済み判定と残り月数の小さな共通getterを追加する方針とする。到達済み状態は基準年月が保有目標年月を**過ぎている場合**であり、同月の0か月とは区別する。既存の未使用 `HomeDisplayData` は復活させず、削除もしない。

想定走行距離の正式な内部計算値は変更せず、Homeでは読みやすさを優先した概算表示とする。

- 1,000km以上：千km単位で四捨五入して表示する。
- 1,000km未満：実数を表示する。
- 内部値は丸めない。Home用の表示処理として扱う。

| 内部値 | Home表示 |
|---|---|
| 99,333km | 約99,000km |
| 99,600km | 約100,000km |
| 999km | 約999km |

HomeとFuture Timelineは**同じ保有目標年月・同じ内部計算値**を使用する。表示精度は画面の役割に応じて異なってよい。Homeは上記の概算表示とし、Future Timelineは既存の詳細表示を維持してよい。

### 保有目標までの登録済み予定費

表示例は**「70歳までの予定費」「2,550,000円」**とし、補足は**「登録している予定費の合計です」**とする。

未登録費用まで含む完全な総額と誤解させないため、「総維持費」「総所有コスト」「必要資金」は使用しない。税金・保険・燃料・未登録故障等を自動的に含む総額にはしない。

### 次の予定費・同月複数件

現在から保有目標までの試算対象に予定費が存在する場合に表示する。単独の表示例は「2027年4月／タイヤ交換／400,000円」とする。

次の予定月に複数件ある場合は、**代表名＋ほか○件＋その月の合計**とする。例は「タイヤ交換 ほか1件／580,000円」。代表名は既存リスト順の先頭とし、新しい並び替えロジックは追加しない。年月と月合計はStep 15-Bのgetterを使用する。

### 予定費0件と一覧導線

保存済み予定費そのものが0件の状態と、保存済み予定費はあるが保有目標までの試算対象が0件の状態を区別する。0円の予定費が存在する状態も、予定費0件と同一視しない。

状態A・Bとも、保有目標までの試算対象予定費が0件の場合は、次の集計ブロックを表示せず、下表の空状態表示へ置き換える。0円表示を複数並べない。

- 保有目標までの予定費（例：70歳までの予定費 0円）
- 次の予定費
- これからの予定費（来年 0円／5年間 0円を含む）

空状態でも、愛車名、保有目標、残期間、保有目標時の車齢・想定走行距離、Future Timelineへの導線は維持する。ただし、保有目標到達済みの場合は次節の規定を優先する。

| 状態 | 表示・説明 | 操作 |
|---|---|---|
| A：保存済み予定費そのものが0件 | **予定費はまだありません**。「車検やタイヤ交換など、これから予定している費用を登録すると、保有目標までのお金の見通しを確認できます。」 | **＋ 予定費を追加**。Future Timelineへの導線も残す |
| B：保存済み予定費は存在するが試算対象が0件 | **保有目標までの予定費はありません**。「予定費はまだありません」とは表示しない | 保存済み予定費を確認・編集・削除できる**予定費を確認する**導線を必ず残す。保有目標にまだ到達していない場合は**＋ 予定費を追加**も表示する |

Bには基準月より前の予定費だけが残っている場合、保有目標より後の予定費だけが残っている場合、保有目標短縮で対象外になった場合等が該当する。

**保存済み予定費が存在する場合はHomeの状態に関係なく予定費一覧へ到達できる導線を残す。**通常状態では「次の予定費」付近の**すべて見る**を使用する。空状態や保有目標到達済みでも、保存済み予定費がある場合は**予定費を確認する**を表示する。到達済みの場合の追加操作は次節の規定を優先する。

**すべて見る**と**予定費を確認する**は既存の予定費一覧画面へ遷移する。既存予定費の確認・編集・削除は、この一覧導線から行い、予定費追加の操作と分離する。

### 保有目標到達済み

基準年月が保有目標年月を過ぎている場合は通常のHome表示を使用しない。過去目標時点の車齢・想定走行距離・残り期間・通常の予定費集計をそのまま表示しない。

推奨表示は以下とする。

- **保有目標に到達しています**
- 設定していた保有目標は **XXXX年XX月でした**
- これからも乗り続ける場合は、新しい保有目標を設定してください。
- **保有目標を見直す**

「保有目標を見直す」は既存の**計画設定画面**へ遷移する。新しい専用画面は作らない。

保有目標到達済みの場合は、状態A・Bにかかわらず本節の到達済み状態の規定を優先する。到達済み状態では**＋ 予定費を追加**を表示しない。現行仕様では登録可能期間が存在せず保存できないため、保存できない操作をHomeに出さない。保存済み予定費が存在する場合のみ「予定費を確認する」を残す。

現行の計画設定では、大型修理への備え目標年齢も過去になっている場合、そちらも変更しないと保有目標の見直しを保存できない場合がある。この既存制約はStep 15-Cでは変更しない。Step 15-Eで大型修理機能の最終的な位置付けとあわせて整理する。

### 近い将来の予定費

見出しは**これからの予定費**とし、**来年**と**5年間**を表示する。既存Step 15-Bの定義・getterを使用する。

- 来年：次の暦年1月〜12月。
- 5年間：現在年を含む5暦年。基準月より前の予定費は含めない。
- 保有目標が途中にある場合は保有目標までで打ち切る。
- Homeには細かな対象年範囲を追加しない。

### 主操作・補助操作・設定・愛車名編集

Homeで最も強い操作は**未来タイムラインを見る**とする。通常状態では補助操作として**＋ 予定費を追加**を表示し、Future Timelineより視覚的に強くしない。保有目標到達済みでは追加操作を表示しない。

通常状態・状態A・状態Bで表示する**＋ 予定費を追加**は、予定費一覧画面を経由せず、**既存の予定費入力／編集用画面を新規追加モードで直接開く**。追加したいという操作から最短で入力へ進ませるため、一覧を見る操作とは分離する。

設定導線と愛車名編集導線は残し、アイコンだけにはしない。推奨構成はアイコン＋**設定**、アイコン＋**愛車名を編集**等、文字で意味が分かる構成とする。40〜70代でも操作が分かりやすいことを優先する。Backup / Restoreへの既存導線を壊さない。

### HomeUpdateと操作通知

既存 `HomeUpdate` enumの `timeline`、`reserve`、`both` 等の意味・構造は変更しない。Step 15-Cで大規模refactorをせず、Home側の表示のみ整理する。推奨表示は以下とする。

| HomeUpdate | Home表示 |
|---|---|
| timeline | 未来タイムラインを更新しました |
| both | 未来タイムラインを更新しました |
| reserve | Homeでは表示しない |

予定費追加・編集・削除と愛車名更新の操作結果は既存SnackBarを使用する。HomeUpdateは**どの計算結果が変わったか**を表す通知として維持する。操作結果の通知とHomeUpdateを二重表示しない。

Homeから予定費を直接追加した場合、保存成功後は**予定費を追加しました**というSnackBarを表示する。この操作ではSnackBarを優先し、**その操作に起因するHomeUpdate表示を抑制する**。「予定費を追加しました」と「未来タイムラインを更新しました」を同時に表示しない。HomeUpdate enum自体は変更せず、大規模refactorも行わない。HomeUpdateは他画面から戻った場合など、計算結果更新を利用者へ知らせる必要がある場面の補助通知として維持する。

青／緑輪郭通知はStep 15-Cでは変更しない。Backup復元成功時の既存動作を維持し、予定費追加時に新規発火させない。通知改善はStep 15-Fで扱う。

### 大型修理・月額積立の扱い

Step 15-Cでは大型修理をHomeの中心から外し、Homeから以下を削除する。

- 大型修理への備え
- 大型修理用積立目標
- 予定費のみ
- 大型修理込み
- 備え分
- 大型修理の詳しく見る
- 前回の試算より

既存の大型修理画面・コード・計算・保存データ・testは削除しない。**Step 15-C〜15-Eの間は通常UIから大型修理画面へ到達できない状態を許容する。**最終位置をStep 15-Eで決めるため、暫定的に設定画面へ移設しない。実装後のtestでは必要に応じて大型修理画面を直接pumpし、既存機能が壊れていないことを確認する。

月額積立はHomeに表示せず、既存ロジックは削除しない。現行Homeですでに非表示なら追加作業は不要とする。最終判断はStep 15-Eで行う。

### 表示例とGolden Sample

本節の表示例は表示イメージであり、実装testの期待値には使用しない。テストでは既存のGolden Sample正式データ・既存test・本書の正式定義を使用する。特に「2027年4月／タイヤ交換／400,000円」等の表示例をGolden Sampleとして扱わない。既存の `lib/sample_data/golden_sample.dart` と `test/sample_data/golden_sample_test.dart` に定義された次の予定費は、**2027年4月／12Vバッテリー／80,000円**である。説明例に合わせてGolden Sampleを変更しない。

### 実装原則・保存形式・作業境界

- Step 15-B getterを再利用する。
- HomeはStateless構成を維持する。
- 新ViewModel追加なし、HomeDisplayData復活なし、新packageなし。
- state管理変更なし、domain model変更なし、大規模refactorなし。
- Persistence形式変更なし、Backup v1変更なし、保存項目追加なし。
- 新しい計算エンジンは作らない。重要数値は既存の決定論的計算を使用する。

実装時の小規模追加として想定するのは、`PlanSession` の保有目標到達済み判定getter・残り月数getter、およびHome用の千km概算表示処理程度とする。

本仕様の文書反映とFlutter実装は別作業とする。実装は明示的な実装開始指示に従い、本仕様の範囲内で行う。外部package、Theme、Android/iOS設定変更等は既存の事前承認ルールに従う。

### Step 15-C実装記録

HomeはStatelessWidgetのまま、保有目標を最上位の情報、未来タイムラインを主操作として構成した。保存済み予定費0件・保存済み予定費あり／試算対象0件・目標同月・目標到達済みを区別し、到達済み状態では通常の目標時点要約・予定費集計・追加操作を表示しない。

`PlanSession.ownershipTargetReached` は基準月が目標月を過ぎた場合のみtrue、`monthsUntilOwnershipTarget` は基準月から目標月への符号付き月差を返す。Home用の `formatHomeMileageKm` は表示だけを千km単位に丸め、既存の詳細距離表示と内部値を維持する。

Homeから既存editorを新規追加モードで直接開き、保存成功後に既存callbackで表示を更新する。追加成功のSnackBarを優先してその操作由来のHomeUpdateを消費し、Timeline／大型修理画面のpendingは保持する。HomeUpdate enum、青／緑輪郭通知、保存形式・Backup v1は変更していない。大型修理の通常UI導線を外し、画面・計算・保存値は維持した。

テストはGolden Sample正式値、残期間と距離表示の境界、空状態A／B、0円予定費、同月複数件、到達済み、直接追加と二重通知抑制、360 logical px・文字倍率3.0を対象とする。大型修理の画面検証は通常UI導線に依存しない直接表示へ更新した。

## Future Timeline：自分と愛車の未来を理解する中心画面

Future TimelineをKeep My Carの中心画面へ昇格する。単に予定費を並べる画面ではなく、**自分と愛車の未来を、お金も含めて理解できる画面**とする。

年ごとに少なくとも、年、Owner年齢、車齢、想定走行距離、予定費、年間予定費を表示する。予定費がない年も、Owner年齢・車齢・想定走行距離を表示する。

Step 8当時の「基準年を含む10年間固定」を上書きし、**原則として保有目標まで表示する**。10年間で打ち切る、または保有目標後まで10年間を埋める方針にはしない。

## 表示・集計期間と目標時点の統一

計算の基準月は既存の `referenceMonth` とする。本節の「現在」「現在年」はこの基準月・基準年に基づく。既存の起動時の端末ローカル年月から基準月を生成する扱いは変更しない。

### 保有目標時点

保有目標時点のOwner年齢・車齢・想定走行距離は、いずれも**実際の保有目標年月時点**で統一する。HomeとFuture Timelineは同じ保有目標年月・同じ内部計算値を使用する。表示精度は画面の役割に応じて異なってよく、Homeの想定走行距離はv0.3の概算表示、Future Timelineは既存の詳細表示を維持してよい。目標年の年末等の別時点の値に置き換えない。

### 来年

「来年」は**次の暦年の1月〜12月**とする。現在が2026年なら2027年1月〜12月を指す。Homeの「来年」とFuture Timelineの翌年行の年間予定費は、同じ試算対象を用いて一致させる。予定費は保有目標までの対象範囲に従って集計する。

### 5年間

「5年間」は**現在の年を含む5暦年**とする。現在が2026年なら2026年〜2030年を指す。ただし、保有目標がそれより前の場合は保有目標までで打ち切る。基準月より前の予定費は含めない。

### 保有目標を過ぎている場合

保有目標年月が現在より前でもFuture Timelineを空にはしない。最低でも**現在年の1行**を表示する。Homeはv0.3の到達済み表示を使用し、「保有目標を見直す」から既存の計画設定画面へ案内する。通常の目標時点補助情報・予定費集計・予定費追加は表示せず、保存済み予定費がある場合の一覧導線は残す。

現在年の行を残すことは、試算対象期間を延長したり、期限超過予定費を現在月へ繰り越したりする意味ではない。

## 予定費の対象と入力機能

### 期限超過予定費の既存仕様の再確認

正式な既存仕様と実装は、**基準月より前の予定費はデータとして保持し、試算から除外し、現在月へ自動繰越しない**という扱いである。Step 15でもこの扱いを維持し、新しく変更したものではない。

Step 15の検討過程で「現在月へ繰り越す仕様だったのではないか」という誤った前提が示されたが、Repository内の過去仕様・Git履歴・実装を確認した結果、そのような正式仕様は存在しないことを確認した。

### 次の予定費

Homeの「次の予定費」は、**現在から保有目標までの対象予定費の中で最も近い年月のもの**とする。同月複数件はStep 15-C v0.3で確定した**代表名＋ほか○件＋その月の合計**を使用する。代表名は既存リスト順の先頭とし、新しい並び替えロジックは追加しない。

### 愛車予定費の位置付け

愛車予定費は**未来を作るための入力機能**として維持し、過去の記録管理へ広げない。編集・削除できる一覧への導線を維持する。MVPでは過去の整備履歴、給油記録、領収書管理、GPS、OBD等を追加せず、普通の車計簿へ機能を広げない。

## 大型修理・月額積立の位置付け

### 大型修理への備え

現行の「○歳までに大型修理用として○円を備える」機能をMVPの主役から外す。ただし、現行の保存データ・計算・画面を直ちに削除しない。既存保存項目である大型修理への備え目標年齢（`reserveTargetAge`）、大型修理予備費（`largeRepairReserveYen`）、現在の愛車専用資金（`currentCarFundYen`）を保持する。

最終位置はStep 15-Eで決める。設定画面の下部等に**「大型修理への備え（任意）」**として残す案は将来の検討候補であり、Step 15-Cでは画面導線を暫定移設しない。Step 15-C〜15-Eの間は通常UIから大型修理画面へ到達できない状態を許容する。現在の入力チェックに大型修理関連項目が関係しており、保有目標見直し時に大型修理への備え目標年齢も変更しないと保存できない場合がある。この制約はStep 15-Cでは変更しない。

### 月額積立

月額積立はStep 15-CのHomeには表示しない。現行の「予定費のみ」「大型修理込み」「大型修理への備え分」「前回の試算より」もHomeから外す。既存ロジックは削除せず、すでに非表示なら追加作業は不要とする。

将来必要なら、**「保有目標までの予定費を均等にすると月約○円」**程度の参考情報1つへ軽くする。参考情報の採否に加え、現行計算を流用するか、単純な月割りとするかを含め、Step 15-Eで決定する。Project Chatではユーザーに分かりやすい単純な月割りを有力候補としているが、本節では計算方法や新しい月割りの式を確定しない。

重要な金額・期間・走行距離等はpure Dartの決定論的計算をSingle Source of Truthとする。AIに重要数値計算を担当させず、UI独自の計算やGolden Sample固有値のDomain Modelへの埋込みを行わない。

## Persistence・Backup / Restoreの継承

Step 15では**現在の保存形式を変更せず、新しい保存項目を追加しない**。以下の新表示情報は既存データから計算する。

- 保有目標までの予定費合計
- 次の予定費
- 来年の予定費
- 5年間の予定費
- 保有目標時点のOwner年齢
- 保有目標時点の車齢
- 保有目標時点の想定走行距離

**現在のBackup v1を維持し、Step 15のためにbackup format versionを変更しない**。大型修理関連データが画面上で目立たなくなっても、旧Backupに含まれている正式な既存データを保持する。復元後に勝手に消したり、予定費へ自動変換したりしない。Step 12・14の保存・復元・検証・Safe Saveの安全性を継承する。

## 通知に関する現行実装の前提

read-only調査で、**予定費追加時には青／緑の画面輪郭通知が現在発火していない**ことを確認した。現行の青／緑輪郭通知はBackup復元成功時の仕組みであり、Future Timeline更新時は別の淡い背景色表示である。

「予定費追加時に青／緑輪郭が出るはずなのに見えない」という状態ではなく、現行実装ではそもそも同じ通知を使っていない。通知の改善はStep 15-Fで行う。

## Step 15-B〜Fの実施順序

| 順序 | 工程 | 目的・範囲 |
|---|---|---|
| 1 | Step 15-B：計算の土台 | 画面を作り直す前に、保有目標時点のOwner年齢・車齢・想定走行距離、保有目標までの予定費合計、次の予定費、来年の予定費、5年間の予定費、Future Timelineの終点を整える。この段階ではHomeの大規模な見た目変更を先に行わない |
| 2 | Step 15-C：Home新設計 | 愛車の未来について一目で分かる要約と、主操作・補助操作・予定費一覧への導線を設計・実装する |
| 3 | Step 15-D：Future Timelineと予定費UI | 保有目標までの中心画面と、未来を作る予定費入力・一覧のUIを整える |
| 4 | Step 15-E：大型修理・月額積立の居場所整理 | 大型修理への備えの最終位置と、月換算の参考情報の採否・方法を決める |
| 5 | Step 15-F：製品版UI/UXとAndroid実機受入 | 通知改善を含む製品版UI/UXを整え、Android実機で受入確認する |

Step 13・14から持ち越した画面の見やすさ、入力の分かりやすさ、通知表現、データ管理画面等のUI/UX改善候補は失効させず、主にStep 15-D〜Fで再評価する。

本節で明示した将来の決定事項は、それぞれの工程で確定する。仕様にない機能、外部package、Theme変更、Android/iOS設定変更等を本節から暗黙に承認されたものとして追加しない。

---

# Phase 05 Step 14 — Manual Export / Import・データ可搬性設計

## Status

Step 14-1〜14-4の正式仕様確定済み。`Step 14-1〜14-4` は仕様策定工程、`14-A1〜14-D` はその確定仕様を実現する実装工程を示す。

実装工程の構成と完了済みcheckpointは以下のとおり。

| 実装工程 | 内容・checkpoint |
|---|---|
| 14-A1：Persistence payload共用化 | 正式入力4field（ownerBirthMonth・Car・PlanConditions・PlannedExpenses）の共用変換処理を分離。内部Persistence形式は変更せず、Step 12の保存・検証動作を維持。実装・検査・独立レビュー完了 |
| 14-A2：Backup v1形式／読込処理 | OS非依存のBackup v1形式（`format`・`exportFormatVersion`・`createdAt`・`data`）とExport / Import変換を実装。既存validationを再利用し、不正Backupを拒否。実装・検査・独立レビュー完了 |
| 14-B：安全な復元処理 | 検証済みcandidateを既存Safe Saveへ接続。保存成功前は正式State不変、成功後のみ一括採用。NoData / Failure / Recovered / readyからの安全な復元、rollback issue時の既存保存状態不明処理、既存処理によるPlanSession / nextId再構築を実装。実装・検査・独立レビュー完了 |
| 14-C1：ファイル保存・選択方式の調査 | `file_picker 13.1.0`・`flutter_file_dialog 3.3.3`を調査し、不採用と判断 |
| 14-C2：Android最小Platform Channel検証 | 保存／読込みの安全契約を実装。Flutterテスト・Kotlin検証・Android build・Pixel 6a基本5項目PASS。実機上書きはProviderの別名保存により未実施。`"wt"`契約をコード・自動テスト・ソース検査で補強。最終read-onlyレビューPASS WITH COMMENTSを経て自前方式を正式採用 |
| 14-C3：本番Export / Import接続 | 14-C2の正式採用方式を本番のバックアップ書き出し／復元処理へ接続。内部経路を実装し、既存Safe Saveを維持。本番UI / UXは14-Dで扱う |
| 14-D：UI / UX | Export / Importの導線・確認・結果表示を実装。自動検査・独立レビュー・手元スマートフォンUX受入完了。初回2択画面は実機未確認／既存自動テストで担保。詳細は本工程の最終実施結果・受入記録を参照 |

14-A1＋14-A2＋14-BのClaude Cowork read-onlyレビュー結果はPASS WITH COMMENTS。Blocker・Major・コード上のMinorはなく、14-Cへの進行はYES。Step 14全体の完了判定は、後述の受入条件に従う。

### Step 14-C2：Android Platform File I/O検証

- `file_picker 13.1.0`は、保存時にStream取得に失敗してもsuccessになり得る経路があったため不採用。
- `flutter_file_dialog 3.3.3`は、Provider例外時にFlutter側へ結果が返らない経路があったため不採用。
- Androidの最小限の自前Platform Channel方式は、Claude Coworkの最終read-onlyレビューPASS WITH COMMENTSを経て正式採用した。本番接続工程への進行可と判断された。
- Pixel 6aの検証用APKで保存・保存Cancel・読込み・読込みCancel・bytes完全一致の基本5項目PASS。既存の大きい同名ファイルへの上書きは、Providerが既存URIを返さず`(1)`付き別ファイルを作成したため未実施であり、アプリ側の失敗ではない。
- アプリは切り詰めmode `"wt"`を要求し、拒否された場合はerrorとする。コード・偽出力先の自動テスト・Android呼出しのソース検査で契約を補強済みだが、`"wt"`を受け付けながら切り詰めない等、仕様に反するProviderの動作までは保証しない。
- `MainActivity`は`FlutterActivity`を維持し、新しいActivityは追加していない。Channel登録・結果転送・cleanupとrequest watermarkの保存／復元を追加し、実I/Oは専用classへ分離している。

### Step 14-C3：本番Export / Import接続（承認済み範囲）

- 本番窓口は正式State → 既存Backup v1 Codec → UTF-8 bytes → 1ファイル保存、および1ファイル読込み → 完全validation → candidate → 既存 `PersistentPlanState.restoreFromBackup` / Safe Saveを接続する。保存成功後だけ正式Stateを採用する。
- candidate取得と復元を分離し、通常／Failureの必要な確認をvalidation成功後に挟める構造にする。NoData・Failureを復元前に正常化しない。rollback issueは既存uncertain契約を維持する。
- 実読込み量は5 MiB以下のみ許可。OS選択画面にtimeoutはなく、URI取得後のI/Oだけ60秒。遅延Successは採用しない。Exportは `"wt"`、write・flush・close完了必須、fallbackなし。ImportはEOF・close完了必須、部分bytes不採用、metadata非依存。
- probe専用経路を本番backup file名称へ整理し、releaseでもsave/readの2methodだけ登録する。package・権限・iOS実装・保存後再読込みは追加しない。
- 本番ボタン配置・確認dialog・最終文言・初回／Failure UI・UX仕上げは14-Dへ残す。

### Step 14-D：本番導線・確認UI・復元UX（承認済み範囲）

- Homeの既存「設定」から計画設定を開き、「データ管理」へ進む。「データを書き出す」「バックアップから復元する」を説明付きで配置する。Homeにバックアップ専用の大きな操作を追加しない。計画設定6項目・Theme・package・Android/iOS設定は変更しない。
- UIは操作開始・確認・結果表示・遷移だけを担当し、JSON生成・解析・validation・OSファイルI/O・Repositoryへの直接保存／削除は行わない。既存BackupTransfer・BackupFileGateway・PersistentPlanState・Safe Saveの責任分界を維持する。
- 通常Importはファイル選択と完全validation成功後だけ「バックアップから復元しますか？」／「現在のデータは、選択したバックアップの内容に置き換わります。」を提示する。操作は「キャンセル」「バックアップから復元する」。通常確認では「元に戻せません」を表示しない。
- Failureは復元・新規設定の2択と既存再読込を提供する。「保存データを読み込めませんでした」「バックアップがある場合は、バックアップから復元できます。バックアップがない場合は、新しく設定して使い始めることもできます。」を表示する。操作開始時にはFailureを正常化しない。Failureのみ、上の「バックアップから復元する」をFilledButtonの主操作、下の「新しく設定する」をOutlinedButtonの副操作とする。
- Failure復元の確認本文は「現在読み込めない保存データは、選択したバックアップの内容に置き換わり、元に戻せません。」。確認の種類はcandidate作成時の状態を固定せず、restore直前の現在のstate.phaseを基準とする。確認中にphaseが変われば現在phaseに対応する確認をやり直す。通常失敗はFailure維持、rollback issueは既存uncertainへ移行する。
- Failureからの新規設定は「新しく設定しますか？」／「現在読み込めない保存データは削除され、元に戻せません。」を表示し、「キャンセル」「削除して新しく設定する」を提供する。削除確定操作はThemeのerror／onError色のFilledButtonで不可逆操作を区別する。確定後だけState層からPersistence層の明示的破棄を呼ぶ。読めるcurrent／backupが見つかった場合や削除前の読込エラーでは破棄しない。current・backup・tempの削除と不存在確認が完了後だけNoDataへ移行して初期設定を開く。削除途中の失敗はuncertainとし、同じRepositoryを再loadして確認する。
- 初回NoDataは「新しく設定する」「バックアップから復元する」の2択。新規は既存10項目初期設定へ進む。復元は通常置換確認を省略し、Safe Save成功後に初期設定を飛ばしてHomeへ進む。
- 書出し成功は「データを書き出しました」、復元成功はHomeで「バックアップから復元しました」と短く表示する。`ScreenSuccessFeedback` により、復元成功後のHome遷移時に青／緑グラデーション輪郭通知を一度だけ表示する。正式State採用・Home遷移・成功通知はSafe Save成功後だけ。Exportは正式State不変。
- ファイル保存／選択Cancel、復元確認Cancel、新規設定確認Cancelはメッセージなし・保存／State変更なし。処理中は重複操作と戻る操作を防ぐ。
- 形式不一致は「このファイルはKeep My Carのバックアップではありません」、新しいversionは「このバックアップは新しいバージョンで作成されているため、このアプリでは読み込めません」。構造／内容不正・破損・5 MiB超過は「バックアップファイルを読み込めませんでした」へまとめる。timeout・接続・予期しないFuture例外は「処理を完了できませんでした。もう一度お試しください」へ落とし、クラッシュや成功扱いにしない。
- 360 logical px・text scale 3.0・文字で意味が分かる操作を維持する。実機でのExport／Import・確認・Home遷移・通知・再起動保持等の受入結果と確認範囲は、以下の最終実施結果・受入記録に記載する。

Export file I/O、restoreの通常save failure、timeout／platform error等は、MVPでは必要以上に細分化せず、既存の一般的なユーザー向けError表示へまとめる。restore／Failure新規設定でuncertainとなった場合は一般Error SnackBarを表示せず、既存の保存状態確認画面に任せる。

本節の最終文言・Failure新規設定契約は、以下のStep 14一般仕様の表示例を具体化する。

#### 復元成功時の輪郭通知

- `ScreenSuccessFeedback` が復元成功後のHome遷移時に青／緑グラデーション輪郭通知を一度だけ表示する。
- Safe Save成功・正式State採用 → Home遷移 → 「バックアップから復元しました」 → Home外周の短時間発光の順とする。最終仕様はduration約2.2秒、外周線4 logical px、blur 8、最大opacity 0.95、青／緑とする。画面内容を塗りつぶさず、輪郭を滑らかに減衰させる。点滅・繰り返し・音・振動は追加しない。
- app UIだけが復元成功時に一時的な通知IDを進め、共通の小さな `ScreenSuccessFeedback` が変更を一度だけ消費する。初期値は既に消費された値として扱い、通常Home表示・再build・再訪問・再起動・Export・Cancel・失敗では再発光しない。通知イベントは保存しない。
- 輪郭はIgnorePointer・ExcludeSemanticsのoverlayとし、既存レイアウトやタップ操作へ影響させない。「動きを減らす」指定ではフェードを行わず短時間の静止した輪郭を表示して消す。BackupTransfer・Codec・Persistenceへ演出責任を追加しない。package・Themeの変更は不要。

#### 最終実施結果・受入記録

Step 14-Dは、本節の承認済み範囲の実装・自動検査・Claude Cowork read-only独立レビュー・手元スマートフォンUX受入を完了した。以下は最終実装状態についての実施結果である。

実装結果：

- 通常利用時は「設定 → データ管理」から「データを書き出す」「バックアップから復元する」を提供する。Importの置換確認はvalidation成功後だけ提示する。
- Failure状態は「バックアップから復元する」「新しく設定する」を提供し、新規設定時は保存データの破棄確認を必須とする。
- 初回起動は「新しく設定する」「バックアップから復元する」の2択を提供する。
- Success / Cancel / Errorの結果表示・取扱いを実装した。Successは成功メッセージ、Cancelはメッセージなし、Errorは本節のユーザー向け表示とする。uncertain時は一般Error SnackBarを出さず、既存の保存状態確認に任せる。
- restore直前にphaseを再確認し、確認中のphase変更時は現在phaseに対応する確認をやり直す。
- 復元成功時はHomeへ遷移し、「バックアップから復元しました」と `ScreenSuccessFeedback` による青／緑輪郭通知を一度だけ表示する。

手元スマートフォンUX受入：

- release APKで通常Export、Export Cancel、通常Import、Import Cancel、復元確認、復元成功、Home遷移、成功メッセージ、復元後データ、再起動後の復元データ保持を期待どおり確認した。
- データ管理導線、ボタン優先順位、確認文、危険操作表示、青／緑輪郭通知を期待どおり確認した。
- 初回起動の「新しく設定する」「バックアップから復元する」の2択画面は、アンインストール後も過去データが復元されたため、実機未確認／既存自動テストで担保とする。
- 輪郭通知は最終仕様で手元スマートフォン再確認済み。以前より視認性が改善し、点灯を意識していれば認識可能と評価した。色・明るさ・点灯時間のさらなる調整はStep 14-Dでは行わず、後日のUI/UX改善で再検討する。この評価はStep 14-Dの要修正・未完了を意味しない。

Remote Pixel 6a Technical Acceptance：途中保留（並行更新検出のため）。別Codexセッションによる想定外のpackage更新と検証対象APKの途中入替を検出した後、単一セッション運用へ切り替えた。端末ロックの可能性もあり、追加操作を行わず端末状態を保全した。アプリ不具合によるFAILではない。主要なExport / Import / UX確認は、上記の手元スマートフォンのrelease APKで実施済みである。

自動検査結果：

| 検査 | 最終実装状態の結果 |
|---|---|
| 関連テスト | 34件PASS |
| 全Flutter test | 765件PASS |
| flutter analyze | PASS |
| Kotlin | 51件PASS |
| Android source check | PASS |
| release APK build | PASS |
| git diff --check | PASS（CRLF→LF警告のみ） |

Claude Cowork read-only独立レビュー結果はPASS WITH COMMENTS、Blockerなし。その後、Failure画面のボタン優先順位、削除確定ボタンの視認性、uncertain時のSnackBar、phase変更中の再確認テスト、`current_step.md`の整理を修正済みである。

#### 後日のUI/UX改善候補

以下をStep 15以降へ持ち越すUI/UX改善候補とする。

- 青／緑輪郭通知の色・明るさ・点灯時間。
- 初回画面の補足説明。
- 初回設定画面から2択へ戻る導線。
- 設定画面上部の「車・所有計画」という名称は、意味がやや硬く直感的でないため、名称を再検討する。
  - 候補例：「愛車と保有計画」「愛車の設定」「車両・保有計画」。
  - 最終名称はStep 15のUI/UX整理で決定する。
- 「データ管理」が設定画面の下部にあり、最下部までスクロールしないと見つけにくい。
  - Homeへ主要ボタンとして出す必要はない。
  - 設定画面内で、より見つけやすい位置への移動やセクション構成の見直しを検討する。

これらは後日のUI/UX改善で再検討可能な事項であり、Step 14-DのBlockerではない。

##### 大型修理への備え分が0円になる場合：仕様確認結果とStep 15以降の持ち越し

塁さんの実機操作で、愛車予定費を設定すると「予定費のみ」と「大型修理込み」が同額となって「大型修理への備え分 ＋0円／月」と表示され、予定費をすべて削除すると両者が同額でなくなり、備え分が正の値へ戻る現象を確認した。最近の開発で計算が壊れたのではないかという疑問に対し、Claude Coworkのread-only調査で以下を確認した。

- 大型修理への備え計算ロジックはStep 9導入時から本質的に変更されておらず、今回の現象は最近の開発による回帰不具合ではない。Step 14のBackup / Restore実装が原因ではない。
- `largeRepairReserveYen` が0円へ上書きされる、PlanConditionsが欠落する、`plannedExpenses` 保存時に大型修理条件が失われるという問題ではない。PersistenceやBackup / Restoreはいずれも本現象の原因ではなく、本現象による保存データの破損リスクは確認されていない。
- 現行Step 9では「愛車予定費のみの必要月額」と「愛車予定費＋大型修理予備費を考えた必要月額」をそれぞれ計算し、その差を大型修理への追加の備え額（`additionalMonthlyYen`）として表示する。予定費対応に必要な一定月額は、予定費の絶対額だけでなく、現在の愛車資金に対する不足額と予定費までの期間によって決まる。近い時期の予定費による不足額への対応に必要な月額を大型修理目標年月まで継続すると、大型修理予備費も同時に確保できることがある。この場合、両方の必要月額が同額となり、追加分が0円になる。大型修理予備費そのものが計算から消えているわけではなく、現行Step 9計算仕様どおりの挙動であり、愛車資金が0円などの場合は比較的小さな予定費でも起こり得る。

Step 12より前はGolden Sampleの現在の愛車資金500,000円を使った固定データ中心で動いていたため、この条件が表面化しにくかった。

「大型修理への備え分 ＋0円／月」という表示だけでは、大型修理予備費200万円等が計算されていないと誤解される可能性がある。塁さんも実機操作時に回帰不具合を疑ったことから、計算バグの修正ではなくUI/UX上の改善事項として、以下をStep 15以降へ持ち越す。AはStep 13のUI/UX販売前改善候補およびStep 15ロードマップにある既存の0円表示改善候補と併せて検討する。

- **A. 追加分が0円の場合の表示改善**：`additionalMonthlyYen == 0` かつ大型修理予備費が設定されている場合、単純な「0円」だけでなく、大型修理予備費が計算から消えたわけではないと分かる表示を検討する。文言例は「追加の積立は不要です」「現在の予定費に向けた積立を続けることで、大型修理予備費も確保できる計算です」。これらは検討例であり、最終文言は確定しない。予備費自体が0円の場合や未設定の扱いと、計算結果の追加分が0円の場合を混同しない。
- **B. 一定月額積立方式の将来再評価**：現行Step 9は基準月から大型修理目標月まで同じ月額を積み立て続ける方式であり、現在の愛車資金に対して近い時期の予定費による不足額が大きくなり、必要月額が高くなる場合も、その月額を予定費支出後から目標年月まで継続する計算となる。現行仕様として正しい一方、実際の家計感覚では予定費支出前と支出後で必要積立額が変わる方が自然な可能性がある。MVPでは一定月額方式の見直しや計算エンジンの大きな変更を行わず、「段階的な積立額」等への変更は将来改善候補として記録する。Step 15での実装を確定しない。
- **C. 未来タイムラインと大型修理予備費の関係確認**：Claude Coworkの調査では、現行の未来タイムラインは大型修理への備え計算結果を直接参照していないことを確認した。製品コンセプト「好きな車に、あと何年乗れる？」と、毎月いくら準備すればよいかを考えるという中心価値との整合から、大型修理予備費をタイムライン上に表示するか、何らかのイベントとして扱うか、現状どおり別画面だけで扱うかをStep 15以降で仕様確認する。大型修理イベントの実装を決定したものではない。

本項は仕様確認結果と改善候補の記録であり、Step 14の要修正・未完了を意味しない。Aの最終表示、Bの計算方式変更、Cのタイムライン上の扱いを、Step 15の実装確定事項として扱わない。

### Step 14-B：検証済みバックアップの安全な復元

- 14-A2の `BackupImportSuccess.data` を受け取る明示的な復元操作を `PersistentPlanState` に追加する。固定ルールの検証を複製せず、既存 `Repository.save(candidate)` / Safe Save / commit callback / notifyを共用する。
- 通常・Recovered・NoData・Failureから開始可能とする。loading・保存中・保存状態不明・他処理実行中は開始させない。Failureの許可は明示的な復元だけとし、通常保存の制約を維持する。
- candidateの予定費を固定し、保存前に独立した `PlanSession` を事前構築する。計算・採番の再構築には既存Session処理を利用し、正式Stateへの採用は保存成功後のみとする。保存後のSession生成例外による保存内容と画面の不一致を避ける。
- 保存成功後の同期的なcommit callbackでowner・Car・PlanConditions・PlannedExpensesを一括採用し、readyへ移行して通知する。保存前に現在の正式データ・Sessionを変更しない。
- candidate準備・Session構築・復元途中の予想外の例外と通常保存失敗では、元の正式データ・Session・開始状態を維持する。`rollbackIssues` がある場合のみ既存uncertainへ移行し、同じRepositoryの再loadを利用する。
- この工程はアプリ内部の復元処理とテストに限定する。ファイル選択・保存先選択・実バックアップファイル操作・UI・package追加・Android/iOS設定変更は含めない。

## Step 14の目的と仕様の位置付け

ユーザー自身がKeep My Carの正式入力データを端末外へ持ち出し、端末故障への備え、Android機種変更、再インストール後の復元、将来のAndroid ⇔ iPhone移行を行えることを目的とする。Keep My Car自身のクラウドバックエンドなしで長期利用できることをMUSTとする。

Step 12のアプリ内部backupはSafe Save / Recovery用であり、ユーザーが保管するManual Exportとは別機能である。Step 12の保存・復旧契約を継承し、本節をManual Export / Importの形式・安全性・UX・受入条件の正本とする。Step 13以下の記録は各工程当時の範囲を示す。NoDataからの導線は本Stepで拡張する。

## Step 14：Importの安全原則

以下をMUSTとする。

1. Import成功前に現在の正式Stateを変更しない。
2. 部分Importを行わない。一部だけ正しいファイルも全体を拒否する。
3. 外部ファイルから内部currentへ直接上書きしない。
4. 対象全体の構造・型・値・Domain整合性を完全検証してからcandidate Stateを生成する。
5. candidateは既存の `KeepMyCarRepository.save(candidate)` / Safe Save経路で保存する。
6. Safe Save成功後だけ、保存したcandidateの全対象データを同時に正式Stateとして採用する。
7. Import失敗、Cancel、不正ファイルではcandidateを採用せず、現在の正式Stateを維持する。
8. Import専用の直接書込み経路を新設しない。
9. 既存Commit-on-saveと保存中の編集・再送信・戻る抑止を維持する。
10. rollback issueでは既存の「保存状態不明」処理を使用する。ディスク上の旧データ維持を保証する通常失敗表示や成功演出を出さず、同じRepositoryの再loadで保存状態を確認する。

Import前データ保護には既存Safe Saveのbackup 1世代を利用する。このbackupはSafe Save / Recovery用であり、ユーザー操作によるUndo機能ではない。「Importを取り消して元へ戻す」機能としては保証しない。初回保存でbackupを作らない既存ルールも維持する。ユーザーが確実に現在データを保持したい場合はImport前にManual Exportを行うよう推奨するが、強制しない。Import専用backup履歴、複数世代backup、Undo履歴、履歴画面、自動Import前Export、自動クラウドbackupは追加しない。OS停止・電源断を含む完全なtransaction保証はStep 12同様に行わない。

## Step 14：Export v1の論理形式

内部Persistence JSONをそのまま公開せず、Export専用の薄いEnvelopeを使う。内部の `formatVersion` と外部の `exportFormatVersion` は別管理とし、内部形式の変更を外部形式へ自動伝播させない。

ファイルは平文UTF-8 JSON、拡張子は `.kmcbackup`。この拡張子は識別用であり暗号化を意味しない。推奨ファイル名は `KeepMyCar_Backup_YYYYMMDD_HHmmss.kmcbackup`（例：`KeepMyCar_Backup_20261001_093800.kmcbackup`）とし、車名等を含めない。

### Envelope

| field | JSON型・意味 |
|---|---|
| `format` | string、`keep-my-car-backup` |
| `exportFormatVersion` | integer、初回は `1` |
| `createdAt` | 必須string、ISO 8601としてparse可能な書出し日時（例：`2026-10-01T09:30:00+09:00`）。Domainの年月とは区別する |
| `data` | object、下記の正式入力データ |

Exportには上記metadataを含める。`appVersion` は必要な場合に任意metadataとして検討できるが、Import互換判定には使わない。MVPの互換判定は `format` と対応する `exportFormatVersion` による。`createdAt` はImport互換性判定、バックアップの新旧優先判定に使用せず、復元するデータ内容そのものには影響させない。対応中の `exportFormatVersion` で未知の追加fieldが存在する場合、そのfieldを無視してImportを継続する。未知fieldを理由に拒否せず、必須field・型・値・整合性検証は省略しない。

古いアプリは対応できない新しいExport versionを拒否する。将来の新しいアプリは可能な範囲で過去versionをImportできる設計とするが、MVPで大規模Migration frameworkは作らない。

### dataと既存Domain / serializerの対応

以下は既存 `KeepMyCarDataDto`、`KeepMyCarJsonCodec`、`KeepMyCarDataMapper` とDomain Modelのfield名・型・年月表現に合わせたExport v1の契約である。Domain fieldを追加しない。表中のfieldは必須で、`memo` だけ値としてnullを許可する（キー欠損とは区別する）。objectはJSON object、配列はJSON arrayとする。

| object | field | JSON型・表現 |
|---|---|---|
| `data` | `ownerBirthMonth` | string、`YYYY-MM` |
| `data` | `car` | object、Car |
| `data` | `planConditions` | object、PlanConditions |
| `data` | `plannedExpenses` | array、PlannedExpense objectの一覧。空配列可 |
| `car` | `name` | string |
| `car` | `firstRegistrationMonth`, `mileageCheckedMonth` | string、`YYYY-MM` |
| `car` | `currentMileageKm`, `annualMileageKm` | integer、km |
| `planConditions` | `currentMileageKm`, `annualMileageKm` | integer、km |
| `planConditions` | `ownershipTargetAge`, `reserveTargetAge` | integer、歳 |
| `planConditions` | `currentCarFundYen`, `largeRepairReserveYen` | integer、円 |
| `plannedExpenses[]` | `id` | integer、既存予定費ID |
| `plannedExpenses[]` | `name` | string |
| `plannedExpenses[]` | `amountYen` | integer、円 |
| `plannedExpenses[]` | `plannedMonth` | string、`YYYY-MM` |
| `plannedExpenses[]` | `basis` | string、`quoted` / `selfEstimate` / `placeholder` |
| `plannedExpenses[]` | `memo` | stringまたはnull |
| `plannedExpenses[]` | `status` | string、`planned` / `completed` |

年月は既存 `validateStorageMonth` と同じASCII数字4桁の年・ハイフン・2桁の月（01〜12）の7文字とする。年月へ日・時刻・timezoneを追加しない。予定費はID、元List順、basis、memo、statusを含めて保持し、同月の表示順や個別同一性を失わない。名称・年月・金額が同じ別IDの予定費は許可する。

Export対象は現在の正式Stateの `ownerBirthMonth`、Car、PlanConditions、PlannedExpensesのみ。FutureTimeline結果、RepairReserve結果、pending、diff、draft、UI一時状態、`referenceMonth`、`nextId`、内部 `formatVersion` は含めない。Import後のderived stateは正式入力から既存の決定論的計算で再計算する。`referenceMonth` は既存どおりアプリ起動時の端末ローカル年月を使用し、ファイルから復元しない。

### OS非依存と機密性

Android内部path、URI、package固有情報、class名、専用identifier、内部directory構造、SQLite等の物理保存方式依存情報を含めない。将来iOSでも同じExport v1をImportできる論理形式を維持し、iOS用の別バックアップ形式を新設する前提にしない。

MVPではdigital signature、秘密鍵基盤、password protection、独自暗号化を導入しない。安全性の中心はImport時のformat・version・structure・type・value・Domain consistency検証とする。ユーザーへ「バックアップファイルには、車両情報や計画金額など入力した情報が含まれます。第三者へ共有しないようご注意ください。」等の注意を表示する。

## Step 14：Import validationと採番

ファイル読込可能・JSON parse可能を確認後、Envelope object、`format` の存在と一致、`exportFormatVersion` の存在・型・対応可否、`createdAt` の存在・string型・ISO 8601としてparse可能であること、`data` の存在・object構造を確認する。`createdAt` の欠損・型不正・ISO 8601形式不正はImport拒否とする。dataは上記schemaの必須field、型、配列構造、年月、金額、走行距離、enum値、ID、ID重複、各予定費と全体のDomain整合性を検証する。欠損を既定値で補完したり、不正項目を捨てて残りだけImportしたりしない。

`.kmcbackup` はUX上の識別用であり、Importの正否は拡張子だけではなくファイル内容で判定する。ファイル名・拡張子が変更されていても、上記のJSON・format・exportFormatVersion・必須構造・Domain validationを含む全検証を満たす正式Keep My Car Export形式ならImport可能とする。逆に `.kmcbackup` でも内容が不正なら拒否する。Android / iOS / クラウドストレージ間の移行でファイル名が変わっても、同じ論理形式で判定する。

Domain検証はStep 12「Persistenceによる保存・復元のvalidation」の時間に依存しない固定ルールを再利用する。具体的には既存 `validateCarName`、`validatePlanConditionsInvariants`、`validatePlannedExpenseInvariants` とMapperの整合性検証に従う。

- Carの名称はtrim前のCR / LF / Tab禁止を確認し、trim後1〜40 runes。予定費名称も既存どおりtrim後1〜40 runesとする。
- 現在走行距離は0〜2,000,000km、年間走行距離は0〜200,000km。資金・大型修理予備費・各予定費は整数0〜1,000,000,000円とする。
- 目標年齢は両方0〜100歳、`reserveTargetAge <= ownershipTargetAge` を要求する。
- CarとPlanConditionsの現在・年間走行距離はそれぞれ一致必須。不一致を自動同期して通さない。
- 保存から時間が経過したこと、目標年月が過去になったこと、予定費が現在の編集可能年月範囲外であることだけを理由に拒否しない。新規入力・編集用の時点依存validationをImportへ適用しない。ownerBirthMonthにも未来の生年月等の新しい業務制約を追加しない。
- IDは既存のinteger型と重複禁止の契約に従い、そのまま保持する。既存Domain / MapperにはIDの正数限定等の値域制約はないため、Import独自の制約や再採番を追加しない。未知の追加fieldはEnvelope節の規則に従って無視するが、未知enum値や必須fieldの欠損・型不正、Domain不正値、ID重複、データ間不整合は全体拒否とする。

`nextId` はExportしない。既存保存・復元経路ではRepository自身が採番するのではなく、復元一覧を受け取る `PlanSession` が `_nextExpenseId = 1` から開始し、各予定費の `id >= _nextExpenseId` の場合に `_nextExpenseId = id + 1` へ更新する（空一覧なら1）。Import後もこの既存処理を再利用し、Import専用の採番ロジックを作らない。新規追加のID消費は従来どおり保存成功後とする。

## Step 14：通常Export / ImportとUI

既存Homeの「設定」は `PlanSettingsScreen` への導線である。この導線を基本に「設定 → データ管理 → データを書き出す / バックアップから復元する」程度の小さな構成とし、不要なバックアップ管理・履歴画面を追加しない。既存の計画設定6項目の意味は変えない。

### データを書き出す

現在の正式State → Export data生成 → Envelope生成 → OS標準保存UI → ユーザーが保存先を選択 → 書込み → 成功の順とする。書込み完了後に「バックアップを書き出しました」等を表示する。Cancelはエラー扱いしない。

保存先への書込み失敗、容量不足、Provider側エラー、OS側I/O失敗では成功表示を出さず、Exportを保存成功扱いにしない。アプリ内部の正式データを変更せず、Error UXに従った平易なエラーを表示する。OS内部エラーやexception等をそのまま表示しない。

### バックアップから復元する

OS標準ファイル選択 → 読込 → Envelope parse → format確認 → version確認 → 構造検証 → 型検証 → 値検証 → データ間整合性検証 → candidate生成 → 置換確認 → `Repository.save(candidate)` → Safe Save成功 → 全正式State採用 → derived state再計算 → Homeの順とする。

validation成功後・save前に、例えば以下を表示する。Cancelでは保存しない。

> 現在のデータを置き換えます
>
> バックアップから復元すると、現在のKeep My Carデータは置き換わります。
>
> 必要な場合は、先に現在のデータを書き出してください。
>
> ［キャンセル］［復元する］

成功後は「バックアップからデータを復元しました」等を表示する。Timeline・Repair Reserve等はファイル内の計算結果を使用せず、復元した正式入力から再計算する。

### 初回起動時の復元

現在データがない `NoData` では「新しく設定する」「バックアップから復元する」の選択導線を設ける。「新しく設定する」は従来の1画面・3区画・10項目の初期設定へ進む。

初回復元もファイル選択 → 通常Importと同じ完全validation → candidate生成 → `Repository.save(candidate)` → Safe Save成功 → 正式State採用・derived state再計算 → Homeとする。置換対象がないため現在データの置換確認は不要とし、成功時は初期設定10項目を省略する。Cancel・不正ファイル・通常保存失敗ではデータを採用せず初回選択画面へ戻れること。rollback issueは初回でも保存状態不明処理を優先する。

既存 `PersistentPlanState.initialize` は空の予定費と新規入力用validationを前提とするため、初回Importにその制約を流用しない。複数予定費を含む過去のバックアップも同じ復元契約で扱い、保存自体は既存Repository / Safe Save経路を共用する。Loaded / Recovered / FailureをNoDataとみなして初期化しない。保存状態不明からの再loadがNoDataの場合も上記選択導線へ進む。

### Failure状態からの復元

`LoadFailure` のFailure画面にも「バックアップから復元する」導線を設ける。FailureをNoDataとして扱わず、既存破損状態を初期化扱いにしない。既存の再読込導線を維持し、Failure状態でも外部バックアップの完全validationを可能とする。

ファイル選択 → 完全validation → candidate生成 → Failure用の復元確認 → `Repository.save(candidate)` / Safe Save → 成功後のみ正式Stateをcandidateへ切替 → derived state再計算 → Homeとする。現在データを正常に読めていないため、通常Importの「現在のデータを置き換えます」とは分けて確認する。例えば「保存されているデータを読み込めません。バックアップから復元できます。」に続けて「バックアップから復元すると、現在読み込めない保存データはバックアップの内容で置き換わり、元に戻せません。」と表示し、ユーザーが復元前に置換と不可逆性を理解できるようにしたうえで、［キャンセル］［復元する］を提示する。

Failureからの復元にも既存Safe Saveを使用するが、現在のcurrentが読めない場合、そのcurrentがbackupへ退避されることは既存Safe Save規則上保証しない。そのため、ユーザーにとって不可逆操作になり得る。特別なbackup処理やUndo機能は追加しない。

Cancel・validation失敗・Import途中の失敗・通常save失敗ではcandidateを採用せず、既存Failure状態を維持する。save失敗だけでFailureを正常化しない。rollback issue時は既存の保存状態不明処理を優先し、正常化せず同じRepositoryの再loadで確認する。

既存 `PersistentPlanState` の通常保存経路はFailure中の保存を拒否するため、FailureからのImportでは検証済みcandidateを既存Repository / Safe Saveへ渡せるようにすることを要求する。Failureを一時的にNoDataや正常状態へ変更して保存制約を回避したり、直接書込み経路を追加したりしない。

### Android Platform I/O

OS標準Document UIを利用する。Exportは `ACTION_CREATE_DOCUMENT` 相当、Importは `ACTION_OPEN_DOCUMENT` 相当とする。広域ストレージ権限、全ファイルアクセス権、フォルダ全体アクセス権は要求しない。1回のImportは1ファイル。Keep My Car自身がGoogle Drive / OneDrive / Dropbox APIへ直接接続しない。

OSファイル選択UIではファイル種別を過度に狭く限定せず、ファイル名・拡張子変更後の正式Exportファイルも選択可能とする。Import可否は前述の内容検証で決定する。

Flutter packageは固定しない。package都合で仕様を変えず、追加が必要な場合は既存開発ルールの事前承認に従う。

### Error UX

ユーザーへJSON、schema、parse error、Repository、exception、stack trace等の開発用語を表示しない。表示例は以下とする。

| 状況 | 表示例・扱い |
|---|---|
| Export書込み失敗 | バックアップを書き出せませんでした。保存先を確認して、もう一度お試しください。 |
| Keep My Car形式ではない | このファイルはKeep My Carのバックアップではありません |
| 破損・構造不正 | このバックアップファイルは読み込めません |
| 対応できない新しいversion | このバックアップは、より新しいバージョンのKeep My Carで作成されています |
| 内容不正 | このバックアップファイルの内容に問題があります |
| 通常のsave失敗（正常に読めた既存データあり） | データを復元できませんでした。現在のデータは変更されていません |
| 初回復元の通常save失敗 | 復元できなかった旨を平易に表示し、初回選択画面へ戻れる |
| Failureからの復元で通常save失敗 | データを復元できませんでした。Failure状態と復元・再読込導線を維持する |
| rollback issue | 既存の保存状態不明処理。旧データ維持を断定しない |
| Cancel | エラー表示なし |

## Step 14：テスト・受入条件

以下は実装後に満たすべき検証要件であり、検証結果の記録ではない。既存テストを都合よく弱めない。

| 分類 | 最低限の検証 |
|---|---|
| Export | 正常Export、format一致、exportFormatVersion = 1、createdAt、ownerBirthMonth・Car・PlanConditions・PlannedExpensesの全field、空予定費、日本語、金額、年月、複数予定費、UTF-8、derived state・nextId非包含。その他の非Export項目も含めない |
| Export失敗 | 保存先書込み失敗（容量不足・Provider側エラー・OS側I/O失敗を含む）で平易なエラーを表示し、成功表示なし・アプリ内部State不変 |
| Import validation | 正常v1、malformed JSON、format欠損・不正、version欠損・新しすぎるversion、data欠損、必須field欠損・型不正、金額不正、年月不正、Domain不正値、ID型不正・重複、Car / PlanConditions不整合、未知enum、日本語、空予定費。createdAt欠損・型不正・ISO 8601形式不正は拒否 |
| Unknown extra field | 対応中のexportFormatVersionで未知追加fieldだけがある場合は、そのfieldを無視してImport成功。必須field欠損・型不正、Domain不正値・データ不整合も併存する場合は拒否 |
| ファイル名・拡張子 | 正しい内容でファイル名・拡張子変更済みでも選択・Import可能。`.kmcbackup` でも内容不正ならImport拒否 |
| データ保持 | 予定費のID・元List順・basis・memo（null含む）・status、同内容の別ID、過去／保有期間外の予定費、時間経過後の目標年月を保持してImportできる。復元後の追加に既存採番を使う |
| Transaction Safety | validation失敗、置換確認Cancel、Repository.save失敗、Import途中exceptionで正式State不変。Safe Save成功時のみcandidate採用、rollback issue時の保存状態不明、部分的に正しいファイルの全体拒否、成功時の全対象データ同時更新 |
| 初回起動復元 | NoData初回選択、新しく設定する、バックアップから復元する、正常Import、初期設定10項目省略、Home、ファイル選択Cancel、不正ファイル、save failure、復元後の完全終了→再起動→Loaded |
| Failureからの復元 | Failure画面の復元導線、NoDataへ変更せず完全validation・candidate生成、通常置換確認と異なる確認、Safe Save成功後のみ採用・Home。Cancel・Import失敗・通常save失敗ではFailure維持、rollback issueでは保存状態不明処理 |
| Step 12回帰 | NoData、Loaded、Recovered、Failure、Safe Save、backup recovery、Commit-on-save、rollback issueの既存テスト維持 |

Golden Sampleのround-tripは、Golden Sample → Export → 別Stateへ変更 → Import → Golden Sampleの正式入力へ完全復元を検証する。正式入力の全fieldと予定費の順序はExport前と完全一致し、derived stateは復元入力から再計算して期待値と一致すること。Golden Sampleの期待値確認には同じ固定referenceMonthを用い、実利用時に現在年月で再計算する契約と区別する。Golden Sample固有値をDomainへ埋め込まない。

### Pixel 6a実機受入

- Export：OS保存UI、任意保存先の選択、`.kmcbackup` の存在、ファイル名仕様、完了表示。
- 通常Import：データを変更した状態からファイル選択、validation、置換確認、復元、Home / Timeline / Repair Reserveへの反映。
- 再起動：Import成功 → アプリ完全終了 → 再起動 → Repository.load → Loaded → 復元State維持。
- 初回起動相当：アプリデータなし → 初回選択 → バックアップから復元 → 初期設定10項目不要 → Home → 再起動後も保持。
- 異常系：破損ファイル・unsupported version拒否、既存データ維持、開発用語非表示。
- release buildでも最低限Export → Import → 完全終了 → 再起動の1往復を確認する。

### 将来iOS受入

Android MVPではiPhone実機確認を完了条件としない。Android側で文書化されたschema、version付き、OS非依存、Android固有値なしを保証する。将来iOS実装時には「Android版で過去に作成されたExport v1ファイルをiOS版でImportできること」を必須Regression Testとする。

### Step 14完了条件

以下をすべて満たした場合だけStep 14完了とする。

| 分類 | 完了条件 |
|---|---|
| Functional | Export・通常Import・初回Import・FailureからのImport・Cancelが可能 |
| Safety | 不正Importで現在データを壊さない、save成功前に正式Stateを変更しない、部分Importしない、Safe Save利用、保存状態不明処理維持 |
| Portability | Export versionあり、OS非依存、Android固有情報なし、将来iOSで読める論理形式 |
| UX | 平易な日本語、開発用語非表示、置換確認、データ機密性注意、初回起動復元導線 |
| Test | 新規テスト・既存回帰・Golden Sample・Pixel 6a・完全終了→再起動・release build基本確認がすべてPASS |

実装と検証、独立read-onlyレビュー、正式変更の承認手順は [Development Workflow](development_workflow.md) とAGENTS.mdに従う。文書への仕様反映だけを実装開始承認やStep 14完了と扱わない。

---

## Step 13 — MVP現状棚卸し・残課題再評価（完了記録・継承）

## Status

Completed.

Step 12までのMVP全体の棚卸し・残課題再評価を完了し、販売可能な初回MVPの範囲を絞り込んだ。次工程をStep 14 Manual Export / Importとした。本Step 13は文書整理のみで、コード実装は行っていない。Step 14の正式仕様と進行状況は本書冒頭を参照する。

## Step 13の目的と完了結果

目的は「Step 12までのMVP全体を棚卸しし、販売可能なMVPまで本当に必要なものを再評価する」こと。

| 対象 | 状態・結果 |
|---|---|
| Step 13-1：現在の実装済みMVP機能棚卸し | 完了。所有者・愛車情報、保有目標・資金設定、予定費CRUD、未来タイムライン、大型修理への備え・必要積立額、ローカル保存・復旧を確認 |
| Step 13-2：正式MVP要件とのGap確認 | 完了。Manual Export / ImportはMUSTだが未実装。販売品質・専用アイコン等の残課題を整理 |
| Step 13-3：未実装機能の必要性再評価 | 完了。定期費用専用機能、修理vs買替え、専用比較UI等を初回MVPから外す |
| Step 13-4：UI/UX改善候補評価 | 完了。年月入力・保存フィードバック・Home等を販売品質改善候補に整理 |
| Step 13-5：販売前必須項目評価 | 完了。Manual Export / Import、専用アイコン、品質検証・販売準備を整理 |
| Step 13-6：MVPから外す項目決定 | 完了。初回除外とリリース後の再評価候補を下記に区別 |
| Step 13-7：販売可能MVPまでの最短ロードマップ確定 | 完了。Step 14〜18の順序と最終判断境界を確定 |

以下はStep 13で確定した初回リリース範囲であり、過去の構想やStep 12以前の実装・検証事実を削除・変更するものではない。後半のStep 12・Step 11の記録は各工程当時の範囲として継承する。改善候補の詳細UIや将来候補の実装を決定したものではない。

## 初回MVPの中核と製品価値

- 所有者情報
- 愛車情報
- 保有目標
- 現在の愛車専用資金
- 将来の予定費
- 未来タイムライン
- 大型修理への備え
- 必要積立額
- 安全なローカル保存
- Manual Export / Import（MUST・未実装）

中心価値は「愛車を希望する年齢まで維持するために、これから予定される整備・修繕費と大型修理への備えを見通し、毎月いくら準備すればよいかを考える」こと。従来の「未来型カーライフ・長期保有コストプランナー」という表現と整合させ、実際のMVP価値を「将来の維持・修繕資金計画」として明確にする。正式な製品名・キャッチコピーは変更しない。

普通の車計簿へ戻らない。車両購入費、減価償却、燃料、税、保険、駐車場、残価等をすべて含む完全なTCO計算アプリとして初回MVPを完成させることは求めない。重要数値は既存の決定論的Planning EngineをSSOTとし、AIへ計算を移さない。

## 販売前MUST：Manual Export / Import

Manual Export / Importは正式MVP要件のMUSTとして維持する。長期利用、端末故障対策、機種変更、将来のAndroid ⇔ iPhone移行のため、ユーザーがデータを持ち出し、復元できることを目的とする。

Step 12の内部 `current / temp / backup` はSafe Save用であり、ユーザーが持ち出せるManual Export / Importとは別物である。内部backupの実装によってこのMUSTを満たしたとは扱わない。形式・Import手順・安全性の正式仕様は本書冒頭のStep 14を参照する。

## UI/UX販売前改善候補

新機能追加ではなく販売品質を上げるための改善候補とする。優先度が高い項目は以下のとおり。詳細UIは今後決定する。

1. 年月入力：現在の `YYYY-MM` 直接文字入力から、年・月を選択しやすいUIへ改善する方向。生年月、初度登録年月、走行距離確認年月等が対象候補。
2. 保存成功フィードバック：現在の青／緑グラデーション点灯は実機で認識しづらく、「光っているのか分からない」という所感がある。販売前に保存されたことを明確に認識できる表示へ改善する。光を強くするだけに限定せず、短い非モーダル表示やチェック表示等も検討可能とする。
3. Home：長い文章、改行、主要数値の視認性、情報の優先順位を改善候補とする。
4. 0円表示：大型修理予備費0円等の表示を再整理する。データ上の0円と「未設定」を安易に同一視しない。
5. 保存失敗／Recovery UI：開発者向け内部用語ではなく、一般ユーザーが理解できる日本語表示を確認・改善する。
6. UI全体の商品感：機能的には成立しているが、見た目がかなり質素という実機所感がある。全面再設計はせず、余白、カード、見出し、文字階層、金額強調、アイコン、ボタン、画面間統一感等を軽量にブラッシュアップする。目標は「派手」ではなく「落ち着いた有料アプリ」。金額・走行距離の可読性も改善対象とする。

### 専用アプリアイコン

現在のAndroidアプリアイコンはFlutterデフォルトのままであり、販売前残課題とする。Keep My Car専用アイコンはGoogle Play販売前に必須。今すぐ作成する必要はなく、UI/UXの方向性が固まった後、Android launcher iconおよびGoogle Play用素材へ展開できる正式デザインを用意する。今回はアイコンファイルを作成・変更しない。

## 初回MVPから明確に除外するもの

- 給油履歴、日々の支出記録、GPS走行記録、OBD連携、SNS、整備工場検索
- 車写真管理を中心機能とすること、フルTCO
- 燃料管理専用機能、高速料金管理専用機能、洗車管理専用機能
- ユーザーアカウント、クラウド認証、クラウドDB、自動クラウド同期、AWSバックエンド、Web管理画面
- 無料版／Pro版等の複雑な商品構成、月額サブスク、広告
- 派手なUI演出、MVPへのAI追加

ここでいう除外は初回MVPの実装範囲から外すことを意味し、過去に検討した費用カテゴリ自体を永久に廃止するものではない。定期費用の構想は保持し、初回販売後のユーザー需要等により再評価可能とするが、将来の実装予定・実装確約とはしない。

## リリース後に必要性を再評価する候補

以下は初回MVPから外す。将来候補として残すが、実装予定・実装確約とはしない。

- 自動車税専用管理、任意保険専用管理
- 車検周期自動生成、法定12ヶ月点検の周期自動生成
- 修理して維持 vs 買替え
- 50万円／100万円／200万円等の複数大型修理ストレステスト比較UI
- AI入力補助等
- 複数車両、英語、USD、EUR

### 定期費用の位置付け

過去仕様の費用範囲である自動車税、任意保険、燃料、高速、駐車場、洗車、車検、法定費用、整備費用、法定12ヶ月点検等の構想は削除しない。Step 13で初回リリース範囲を再評価し、専用の定期費用入力・自動計算機能の完成は初回MVPに要求しない。必要な費用は現状の予定費として手動登録できる余地がある。専用の周期管理等は将来必要性を再評価する。

### 修理して維持 vs 買替え

構想は廃止しないが初回MVPから外す。多数の前提入力と複雑な比較モデルが必要で、サポート負荷を増やし、初回MVPの中心価値をぼかすため。初回リリース後、実ユーザー需要を確認して必要性を再評価する。

### 大型修理ストレステスト

実装済みの「目標年齢までに任意の大型修理予備費を積み立てる」機能はMVP中核として維持する。ここでの目標年齢は既存の大型修理への備え目標年齢であり、保有目標年齢へ置き換えない。

50万円、100万円、100万円×2回、200万円等を横並び比較する専用シナリオUIは初回MVPへ追加しない。ユーザーは大型修理予備費を変更して複数条件を試せる。専用比較UIはリリース後に必要性を再評価する。

## iOSの位置付け：Android初回MVP後の後続工程

現時点はWindows開発であり、iOSはMac導入後に進める後続プラットフォーム工程とする。英語・USD・EUR・複数車両等の必要性そのものを再評価する任意機能とは区別し、初回Android MVP完成のブロッカーにしない。Android版完成をMac購入まで止めない。実際のApp Store公開時期はその時点で改めて判断し、直ちに販売することを確定するものではない。

Android ⇔ iPhoneのデータ可搬性はMVP全体のMUSTとして維持する。ただし初回Android MVPでiOSアプリ自体の実装は要求しない。Exportの形式・将来iOS互換性の受入条件は本書冒頭のStep 14を参照し、iOS版やOS間移行が実装済みであるとは扱わない。

## Step 14〜18の正式ロードマップ

以下の順序をStep 13の成果として確定する。各工程の詳細仕様や実装済み状態を意味しない。

| 工程 | 目的・主対象 |
|---|---|
| Step 14：Manual Export / Import | ユーザーデータの持ち出し、復元、機種変更、将来のOS間移行基盤、Import安全性。正式仕様は本書冒頭参照 |
| Step 15：UI/UX販売品質改善 | 年月入力、保存成功フィードバック、保存失敗／Recovery表示、Home、0円表示、金額・走行距離の可読性、UI全体の商品感、Keep My Car専用アプリアイコン。新しい大型機能は追加しない |
| Step 16：Release Candidate品質検証 | 主要ユーザールート、異常系、Export / Import、Safe Save / Recovery、複数画面サイズ、Golden Sample回帰、`flutter analyze`、`flutter test`、Android release、Claude Cowork read-only最終レビュー |
| Step 17：Android / Google Play販売準備 | 正式商品名確認、専用アイコン・Store素材、スクリーンショット、ストア説明、Privacy、利用条件／免責、FAQ、サポート方針、価格、Google Play提出準備 |
| Step 18：販売最終判断 | 実際に公開するか、修正してから公開するか、公開を見送るかを塁さんが最終判断 |

Step 16完了を「アプリ本体MVP完成」の候補境界とする。Step 17まで進んでも自動的には公開しない。

初回は買い切り型を優先し、サブスク依存を避け、サーバ費不要、継続人間サポートを極力減らす既存方針を維持する。価格は未決定。無料版／Pro版等の二重構成は初回MVPに追加しない。

---

## Step 12 — Local Persistence Baseline（完了記録・継承）

Phase 05 Step 12 Local Persistence Baseline / App Integrationは正式完了。承認済みのStep 12-A〜Eに基づくE1〜E3cの実装・検証、およびProject Chat・Claude Coworkの最終レビューを完了し、Claude Cowork最終判定はPASS（Critical・Major・Minorなし）とする。以下のStep 11および愛車表示名の承認済み仕様は継承する。

## Step 12の承認・実装状態

| 対象 | 現在の状態 |
|---|---|
| Step 12-A：保存要件 | 承認済み |
| Step 12-B：Version付きJSON方式 | 承認済み |
| Step 12-C：JSON形式・安全保存・1世代backup方針 | 承認済み |
| Step 12-D：Persistence責務分離・保存成功後反映方針 | 承認済み |
| Step 12-E：実装範囲・受入条件 | 承認済み |
| Step 12-E1：JSON保存形式・変換基盤 | 実装済み・正式完了判定済み |
| Step 12-E2：安全なローカルファイル保存・1世代backup・復旧 | 基盤実装・レビュー完了 |
| Step 12-E3a：所有者生年月Persistence追加＋E2テスト補強 | 実装・レビュー完了 |
| Step 12-E3b：初回設定・起動時読込・画面保存接続 | 実装・レビュー完了（PASS WITH COMMENTS） |
| Step 12-E3c：保存候補直接採用・統合テスト補強・Android release実機確認 | 実装・検証・独立レビュー完了 |

E1ではCar・PlanConditions・PlannedExpenseの保存専用DTO、Domainとの相互変換、JSON encode/decode、formatVersion = 1、構造・型・年月・versionの検証と単体テストを実装する。Domain ModelにJSON責務を追加せず、Domain validationを再利用する。

E2では実ファイル保存・読込、current / temp / backup、backupからの復旧判定を実装する。UI接続、起動時load、PlanSession保存接続はE3bで実装。Import / Exportは未実装とする。

### E2の保存・復旧基盤

- Application側の境界は`KeepMyCarRepository.load()`と`save(snapshot)`とし、File APIと保存場所取得はStorageへ隔離する。Mapperから結果に影響しない生年月・基準年月引数を除去し、予定費の固定validationもDomain側で共用する。
- `path_provider`のApplication Support領域を使用する。同一directory内の`keep_my_car.json`（current）、`keep_my_car.tmp`（temp）、`keep_my_car.backup.json`（backup）の3ファイルとする。
- 保存は固定validation・JSON生成 → UTF-8 temp書込み（flush）→ 実読込・Codec／Mapper再検証・候補との一致確認 → 正常currentをbackupへ退避 → tempをcurrentへ昇格 → current再検証・一致確認の順とする。初回保存ではbackupを作らない。
- backupは直前正常currentの1世代だけ保持する。不正tempではcurrent／backupを変更しない。不正currentをbackupへ退避せず、既存backupを保持する。
- renameの完全な原子性は前提にしない。退避・昇格・最終検証の失敗時は、退避前の内容からtemp経由でcurrent、次いでbackupの復元を試みる。currentの復元にも失敗した場合はbackupを追加変更せず、元エラーと復元失敗原因を返す。OS停止・電源断を含む完全なtransaction保証は行わない。
- loadはcurrent正常なら`Loaded`、current欠損／破損等かつbackup正常なら`Recovered`、両方欠損なら`NoData`、利用可能な正常データがなければ`LoadFailure`を返す。読込エラーは欠損と区別する。
- loadはファイルを書き換えない。tempのみなら`NoData`とし、自動昇格しない。正常currentとtempがあればcurrentを採用する。Golden Sampleや空データへ自動フォールバックしない。
- 同一保存directoryには単一Repositoryを所有させ、実行中ガードにより同時saveとsave中のloadを拒否する。エラーは発生段階・元例外・stack traceを保持する。ユーザー向け通知はE3とする。

### E3aの保存Snapshot拡張・受入条件

- 最上位の必須fieldとして`ownerBirthMonth`を保存する。DTO／JSONは既存年月形式と同じ`YYYY-MM`文字列、Domainとの値集合は既存の`YearMonth`とする。欠損・null・型違い・不正年月は拒否する。未来の生年月や年齢上限等の新しい業務制約は追加しない。
- 保存SnapshotはownerBirthMonth・Car・PlanConditions・PlannedExpensesで構成する。E3aの形式拡張後も`formatVersion = 1`を維持する。所有者生年月のない旧形式へ既定値を補完しない。
- `referenceMonth`は保存しない。E3bでアプリ起動時の現在年月から生成する値とする。Golden Sampleの所有者生年月1970-04とStep 8／9のRegressionを往復テストで維持する。
- E2補強テストでは、正常current＋破損backupからの保存、破損current＋backupなしからの保存、current復元成功＋backup復元失敗で最新の正常な旧currentを保持することを確認する。`rollbackIssues`は維持し、E3bで保存状態不明を識別するために使う。
- 同じ保存directoryに複数Repositoryを同時利用した場合の安全性は保証しない。E3bではKeepMyCarAppがアプリ全体でRepositoryを1つだけ所有する。E3aではApp接続やglobal lockは実装しない。

### E3bのApp・UI接続

- KeepMyCarAppがRepositoryを1インスタンスだけ所有し、Application State経由のcallbackで画面の保存要求を受ける。各画面ではRepositoryを生成しない。
- 起動時はLoadingを表示し、load完了までHomeやGolden Sampleを表示しない。referenceMonthは起動時の端末ローカル年月から生成し、保存しない。
- NoDataでは1画面・3区画・10項目の初期設定へ進む。走行距離確認年月は現在月、愛車専用資金・大型修理予備費は0円、目標年齢は未入力とする。既存Domain validationを共用し、ownerBirthMonth・Car・PlanConditions・空の予定費一覧の保存成功後だけHomeへ進む。通常失敗では入力を維持する。
- Loadedでは保存Snapshotを正式Stateとして採用し、Step 8／9を再計算する。Recoveredではbackup内容でHomeへ進み復旧通知を表示するだけで、ファイルを修復・削除しない。Failureでは専用画面から同じRepositoryで再読込でき、自動初期化・削除はしない。
- 愛車名・Plan Settings・予定費追加／編集／削除は候補Snapshotを保存してから正式反映する。通常SaveFailureでは旧正式State・計算結果・draftを維持する。愛車名だけでは再計算せず、設定・予定費の変更では既存ルールで再計算する。Carの走行距離2項目も設定の保存成功後だけ同期する。
- 保存中は編集・再送信・戻る操作を抑止する。成功通知と既存の更新フィードバックはPersistence成功後だけ発生する。nextIdは保存せず、復元した予定費IDから再構成する。
- rollbackIssuesがあるSaveFailureは保存状態不明の専用画面へ進み、成功演出を出さない。「保存状態を確認する」で同じRepositoryを再loadし、Loaded／Recoveredならディスク内容を新たな正本として採用、Failureなら読込失敗画面、NoDataなら初期設定へ進む。
- 通常起動でGolden Sampleは生成しない。Golden Sampleは既存のtest／regression用として維持する。Export／Importは未実装とする。
- Pixel 6aのdebug実機でアプリデータ消去 → 初期設定 → 保存 → 完全終了 → 再起動後のLoadedを確認済み。スクリーンショットはRepository外のTempへ保存する。

### E3cの候補採用・統合検証

- Plan Settingsと予定費追加／編集／削除では、保存前の検証・候補作成と保存成功後の正式採用を分離する。Repositoryへ渡したPlanConditions・Car・immutableな予定費一覧をそのまま正式採用し、同じ入力から作り直さない。採用後は既存のStep 8／9再計算・pending・差額判定を維持する。失敗した追加ではIDを消費しない。
- 実Persistence統合テストは専用temporary directoryを使用し、NoData → 初期設定10項目 → 実保存 → App破棄・再生成 → 実読込 → Homeと全保存値の復元を確認する。Application Supportの実データは使用しない。
- 初期設定の幅360px・文字倍率3.0テストではviewInsets.bottom = 300を設定し、キーボード相当領域がある状態で入力欄と保存ボタンへの縦スクロール・overflowなしを確認する。
- Pixel 6aでrelease APKのビルド・インストール、データ消去後の初期設定 → 保存 → 完全終了 → 再起動後Loadedを確認済み。DEBUGリボンなし、Application Support取得を含むpath_provider経由の保存・読込が動作した。release内部JSONの直接読取は非debuggableの権限制限で未確認とし、JSON全項目は実ファイル統合テストで確認する。
- m-1修正後のdebug版でもPlan Settingsの走行距離変更 → 保存 → 完全終了 → 再起動を確認し、保存JSONのCar／PlanConditions両方が60,000kmへ同期していることを確認済み。debug／release双方で保存再起動確認済みとする。Android設定・署名設定は変更しない。

### Persistenceによる保存・復元のvalidation

- 保存時に正常だったユーザーデータを、時間が経過しただけで破損データ扱いしない。後の年月に復元した状態を、そのまま再保存・再復元できること。
- Persistenceによる保存・復元では、時間に依存しない同じ固定validationのみを使用する。保有目標年齢と現在年齢の比較、大型修理目標年月と現在月の比較、予定費の編集時年月範囲は保存・復元の可否判定から除外する。
- 数値の絶対範囲、`0 <= ownershipTargetAge <= 100`、`0 <= reserveTargetAge <= 100`、`reserveTargetAge <= ownershipTargetAge`、型・必須値等の時間に依存しない不変条件は適用する。両目標年齢の固定範囲は0〜100歳とし、固定ルールはDomain側で共通化して保存層へ二重実装しない。
- 既存の新規入力・編集時validationは従来どおり維持する。
- 保存Snapshotでは`Car.currentMileageKm == PlanConditions.currentMileageKm`および`Car.annualMileageKm == PlanConditions.annualMileageKm`を要求する。不一致なら全体の復元失敗とし、どちらへの自動同期も行わない。

## Step 11 — 愛車予定費 CRUD Baseline（継承）

## 実装状態の整理

Step 7〜11は完了済みであり、第29節の愛車表示名編集も実装済みとする。既存機能の実装状態を以下のとおり整理する。Step 12の完了状態は上記の承認・実装状態に従う。現在の工程は本書冒頭のStatusに従う。

| 対象 | 現在の実装状態 |
|---|---|
| 費目名称の自由入力／「その他」カテゴリを設けず具体的な名称で管理 | 実装済み |
| プリセット選択UI | 未実装 |
| 車検周期選択UI | 未実装 |
| 繰り返し／周期登録・自動繰り返し生成・周期展開calculator | 未実装 |
| ローカル永続化 | E1／E2基盤とE3bのUI・起動時読込・保存接続を実装済み |
| 手動Export／手動Import | いずれも未実装 |
| Backup / Restore基盤 | E2の1世代backup・復旧判定、E3bの復旧通知UIを実装済み |
| Android ⇔ iPhoneのデータ移行 | 未実装 |

プリセット候補＋自由入力、車検周期選択、必要に応じた繰り返し／周期登録は構想として維持するが、Step 7〜11の実装済み範囲には含めない。Step 13の再評価により初回MVPには要求せず、リリース後に必要性を再評価する候補とする。候補一覧と車検周期の方針は [Product Baseline「費目入力」](product_baseline.md#費目入力) を正本とする。既存の `MaintenanceCost` 等のモデルは、周期選択・生成・計算機能が実装済みであることを意味しない。

手動Export / Importによるバックアップ・復元とデータ移行は、[Product Baseline「Backup / Data Portability」](product_baseline.md#backup--data-portability) に定めるMVP全体のMUSTである。第1節のStep 11対象外という範囲は維持し、MVP全体で不要という意味にはしない。現在は上表のとおり未実装であり、Step 12-E1／E2にも含めない。保存方式は上記Step 12の承認方針に従う。

## 既存仕様との関係

Step 7〜10の確定仕様を継承し、本書で承認された予定費CRUDと関連する表示・集計・再計算・更新フィードバックを追加する。
既存仕様はGit履歴の以下の `docs/current_step.md` を参照する。

- Step 7「愛車予定費」：`f46062d`
- Step 8「未来タイムライン」：`6c4cc06`
- Step 9「大型修理への備え」：`fc9f602`
- Step 10「計画設定」：`4eb774b36c454c432bfe1de2a28f519ae8593d9c`

Step 7の一覧表示を継承し、追加・明示的な編集操作・削除・空一覧案内を本書の範囲で拡張する。表示用の並べ替えで元Listの順序を変更しない。年間合計の対象は第14〜17節に従う。

Step 8は `referenceMonth` の年を含む10年間の表示期間、referenceMonth基準、年齢・車齢・走行距離計算を維持する。保有目標に合わせて10年間の表示期間を延長・短縮しない。

Step 9は既存の正式計算式、`referenceMonth` から大型修理への備え目標年月まで（両端を含む）の計算期間、および計算不能状態の扱いを維持する。保有目標年月を備え目標年月の代わりに使用しない。

Step 10の6設定項目、編集中状態と正式状態の分離、一括反映、各計算系の最大再計算回数、更新フィードバック、現在のHome表示を継承する。本書第14節で承認された保有目標短縮・再延長による予定費の試算対象の変化は反映する。Step 10時点の「保有目標年齢だけの変更では主要計算値を直接再計算しない」という扱いは、この試算対象の変化まで反映不要とする意味ではない。既存の設定変更による再計算と合わせても、1回の反映につきStep 8・Step 9はそれぞれ最大1回とする。

更新フィードバックはStep 10の正式結果比較・画面ごとの未確認情報を継承する。影響を受けない画面の既存未確認情報、および変更なし操作時の既存未確認情報・差額情報を保持する。未確認のまま A → B → C と正式結果が変化した場合は B → C を比較し、Step 9の差額表示対象は引き続き「大型修理込み」のみとする。

重要な金額・期間等の計算は既存のdomain側の決定論的ロジックをSingle Source of Truthとし、AIやUI独自の近似計算へ移さない。Golden Sample固有値をDomain Modelへ埋め込まない。

表示例はGolden Sampleの実値を意味しない。Golden Sampleの正本はRepository内の既存データとし、説明例に合わせて変更しない。

## Step 11の目的

ユーザーが将来の愛車維持費を、

- 追加
- 編集
- 削除

でき、その変更が、

- 愛車予定費一覧
- 年間合計
- 未来タイムライン
- 大型修理への備え

へ正しく反映される状態を作る。

Keep My Carの中心思想である、

「愛車を長く維持するための未来資金計画」

を強化する機能であり、整備履歴アプリや一般的な車計簿へ変質させない。

---

## 1. Step 11で実装する範囲

以下をStep 11対象とする。

- 予定費の新規追加
- 予定費の編集
- 予定費の削除
- 一覧の再集計
- Step 8「未来タイムライン」への反映
- Step 9「大型修理への備え」への反映
- 保有期間外予定費の表示
- 空一覧表示
- 入力検証
- 追加・更新・削除後の短い完了通知

以下はStep 11対象外。

- SQLite
- 永続保存
- アプリ再起動後の入力保持
- バックアップ／復元
- CSV
- クラウド同期
- プリセット
- 周期・繰り返し登録
- 整備履歴
- 通知
- AI
- 車種別故障予測
- 写真・見積書管理
- 整備工場管理

Step 11ではアプリ再起動後にGolden Sampleへ戻って構わない。

---

## 2. 予定費1件のデータ

予定費1件は内部的に以下を持つ。

- 一意ID
- 項目名
- 予定年月
- 金額

ユーザーが編集するのは、

- 項目名
- 予定年月
- 金額

の3項目のみ。

既存の `PlannedExpense` が持つ `basis`、`status`、`memo` も維持する。`basis` と `status` はnon-nullable requiredフィールドであり、一意IDの追加を理由に既存フィールドを削除しない。

Step 11で新規予定費を生成する場合は、以下の固定値を使用する。

- `basis = ExpenseBasis.placeholder`
- `status = PlannedExpenseStatus.planned`
- `memo = null`

これら3項目は将来Stepで正式な意味付けを行うまでは固定値とし、Step 11ではユーザー編集対象にしない。新たな入力欄は追加しない。

一意IDは、同一内容のduplicateを個別に識別するために使用する。

IDの具体的実装方式は、既存Repository構造を確認したうえで決定する。

SQLiteを前提とした過剰設計は行わない。

---

## 3. 項目名

- 必須
- 自由入力
- 最大40文字
- 「その他」という固定項目は作らない
- 保存時に前後の半角・全角空白を除去する
- 空白除去後に空文字となる場合は保存不可
- 内部の空白は保持する

例：

- 車検
- 法定12か月点検
- タイヤ交換
- ブレーキローター・パッド一式交換
- 48Vバッテリー
- エアコン修理

---

## 4. 予定年月

年月単位とし、日付単位は扱わない。

新規追加および通常編集で選択可能な範囲：

`referenceMonth ～ 現在の保有目標年月`

新規追加時の初期値：

`referenceMonth`

referenceMonthより前、または保有目標年月より後の年月は新規保存不可。

---

## 5. 金額

- 必須
- 日本円
- 整数のみ
- 範囲：`0～1,000,000,000円`
- 空欄不可
- 負数不可
- 小数不可
- 1,000,000,001円以上不可
- 0円は正式に許可する

空欄と0円は別扱い。

入力中にリアルタイムのカンマ整形を必須としない。

保存後・一覧表示等では既存の金額表示方針に従う。

---

## 6. duplicate

同一の、

- 項目名
- 予定年月
- 金額

を持つ予定費が複数存在しても許可する。

自動統合しない。

警告も不要。

各項目は一意IDによって個別に編集・削除する。

---

## 7. 新規追加画面

追加と編集は同じ画面を共用する。

新規時：

- 画面タイトル：「予定費を追加」
- 項目名：空欄
- 予定年月：referenceMonth
- 金額：空欄
- 主操作：「追加」
- 削除操作：表示しない

正常追加時：

1. 新しい一意IDを付与
2. 元List末尾へ追加
3. 一覧表示時に既存ルールで並べ替え
4. 年間合計更新
5. 必要なStep 8再計算
6. 必要なStep 9再計算
7. 一覧画面へ戻る
8. 「予定費を追加しました」と短く表示

---

## 8. 編集画面

編集時：

- 画面タイトル：「予定費を編集」
- 現在値を表示
- 主操作：「保存」
- 「この予定を削除」を表示

編集途中では正式データを変更しない。

「保存」時に正式反映する。

既存予定費を編集しても、一意IDは変更しない。

編集によって年月が変わっても、元List上のidentity・順序基準は維持する。

---

## 9. 編集開始UI

重要：

**行全体タップで編集画面へ遷移する仕様は採用しない。**

理由：

縦スクロール中に予定費行へ触れた際、意図せず編集画面へ遷移する誤操作を避けるため。

各予定費行には、ユーザーが意図的に操作できる明示的な、

**「編集」**

操作を設ける。

ターゲット層を考慮し、意味が伝わりにくいアイコン単独を第一選択としない。

十分なタップ領域を確保する。

予定費行本体は情報表示を主目的とする。

---

## 10. 戻る操作

AppBarの戻る、Androidの戻る等で編集画面を離れた場合、編集中の内容は破棄する。

Step 11では、

「変更内容を破棄しますか？」

等の追加確認ダイアログは設けない。

入力項目が3項目のみであるため、MVPでは操作の簡潔さを優先する。

---

## 11. 削除

削除は編集画面からのみ行う。

一覧画面には直接削除操作を置かない。

スワイプ削除も採用しない。

削除操作時は確認ダイアログを表示する。

例：

「この予定費を削除しますか？」

確認後に削除を確定する。

### 削除方式

**Step 11では物理削除とする。**

対象予定費を現在の予定費Listから削除する。

`isDeleted`、削除日時、ゴミ箱等の論理削除機構は導入しない。

理由：

- SQLite未導入
- クラウド同期なし
- 復元機能なし
- 監査履歴要件なし
- 現時点では論理削除のユーザー価値がない
- 一人開発として不要な複雑性を増やさない

将来、ゴミ箱・復元・同期等が必要になった場合に改めて検討する。

削除後：

- 対象IDの1件だけ削除
- duplicateの他項目は残す
- 年間合計更新
- Step 8再計算
- Step 9再計算
- 一覧へ戻る
- 「予定費を削除しました」と表示

削除確認をキャンセルした場合は何も変更しない。

---

## 12. 一覧画面

Step 7の既存一覧UIを基本的に維持する。

維持する既存仕様：

- 年月昇順
- 同月は元List順
- 年単位グループ
- 年間合計
- 名称／年月／金額表示
- duplicate許可
- 横スクロールなし
- 縦スクロール
- 360 logical px対応
- text scale 3.0対応
- 金額ellipsis禁止

追加するもの：

- 「予定費を追加」導線
- 各予定費行の明示的な「編集」操作
- 保有期間外表示
- 空一覧表示

「予定費を追加」は、アイコンだけで意味を伝える設計より、文字で意味が分かるUIを優先する。

明示的な「編集」操作、「現在の保有期間外」表示、「予定費を追加」導線、空一覧表示、追加・更新・削除完了通知、第16節の「現在の試算対象なし」表示を含む、Step 11で新たに追加する表示要素にも、既存Step 7のUI制約を適用する。

- 360 logical px対応
- text scale 3.0対応
- 横スクロール不要
- 重要情報の欠落なし
- 金額ellipsis禁止

「編集」操作は40〜70代中心のユーザーが十分認識できる表示とタップ領域を確保する。これらの条件を満たす具体的なWidget構成やレイアウト実装方法は固定しない。

---

## 13. 表示順

既存仕様を維持する。

表示順：

1. 予定年月昇順
2. 同月の場合は元List順

新規追加項目は元List末尾へ追加する。

その後、表示時に年月順へ並べる。

編集で年月が変わっても元List上の位置は変えない。

---

## 14. 保有期間外予定費

保有目標年齢を短縮した結果、既存予定費が現在の保有期間外になっても削除しない。

以下の扱いとする。

- List上には保持
- 一覧にも表示
- 「現在の保有期間外」と控えめに表示
- エラー扱いしない
- 赤い警告等の強い表現を必須としない
- 年間合計には含めない
- Step 8計算に含めない
- Step 9計算に含めない

保有目標を再び延長し、予定年月が有効範囲へ戻った場合は、自動的に試算対象へ戻す。

手動の有効化操作は設けない。

ユーザーデータを保有目標変更だけで自動削除しない。

### Step 9における除外原則と受入検証

保有期間外予定費をStep 9の入力対象としない原則は維持する。ただし、現行の `reserveTargetAge <= ownershipTargetAge` 制約下では、Step 9の計算窓 `referenceMonth ～ reserveTargetMonth` はもともと保有期間内に収まる。

そのため、保有目標短縮による保有期間外除外そのものを原因とするStep 9の数値変化は観測できず、その数値変化を受入検証の必須条件にしない。除外の数値的な確認は主として年間合計およびStep 8側で行う。Step 9については既存計算窓と対象外予定費が混入しないことを確認する。

この除外原則は、将来計算窓や条件が変更された場合にも意図しない対象混入を防ぐための防御的仕様として残す。

---

## 15. 範囲外予定費の編集

保有期間外となった既存予定費も、

- 一覧表示可能
- 編集画面を開ける
- 削除可能

とする。

現在登録済みの範囲外年月は編集画面で表示できなければならない。

ただし、その項目を編集して保存する場合は、予定年月を現在の有効範囲、

`referenceMonth ～ 保有目標年月`

へ戻す必要がある。

範囲外のまま名称・金額だけ変更して保存することはStep 11では許可しない。

---

## 16. 年間合計

年間合計は、現在の試算対象となっている予定費のみを集計する。

保有期間外予定費は年間合計へ含めない。

ある年の予定費がすべて保有期間外の場合、

「年間合計 0円」

と同一視せず、

**「現在の試算対象なし」**

等、対象外であることが分かる表示を使用する。

0円予定費と試算対象外は別概念として扱う。

---

## 17. 0円予定費

0円予定費は正常な予定費として扱う。

例：

- 項目名：バッテリー交換
- 予定年月：2029年6月
- 金額：0円

範囲内であれば一覧へ通常表示し、年間集計・試算上も0円の予定として存在する。

「予定費なし」と0円予定費は区別する。

---

## 18. 空一覧

予定費が0件の場合、単なる空白画面にはしない。

例えば、

「予定費はまだありません」
「将来予定している車検やタイヤ交換などを登録できます」

等の短い説明を表示する。

近くに「予定費を追加」導線を置く。

文言の最終調整は既存UIトーンに合わせる。

---

## 19. 再計算

予定費の正式Listが実際に変更された場合のみ再計算する。

1回の追加・変更・削除につき、

- Step 8：最大1回
- Step 9：最大1回

とする。

以下では再計算しない。

- 編集画面を開くだけ
- 入力途中
- 年月選択途中
- 戻る操作による編集破棄
- Navigation
- Widget build
- text scale変更
- keyboard表示
- pending feedback消費

---

## 20. 変更なし保存

編集画面を開き、正式値と実質的に同じ内容のまま「保存」を押した場合：

- List変更なし
- Step 8再計算なし
- Step 9再計算なし
- 「予定費を更新しました」通知なし

一覧へ戻ってよい。

比較時は、保存時の正規化後の値を考慮する。

例：

項目名の前後空白を除去した結果、正式値と同じであれば変更なしとして扱える。

---

## 21. 更新フィードバック

予定費一覧では操作結果として短く、

- 「予定費を追加しました」
- 「予定費を更新しました」
- 「予定費を削除しました」

を表示する。

新しい大げさな演出やモーダル通知は導入しない。

予定費変更によりStep 8／Step 9の正式結果が変化した場合は、Step 10で確立した更新フィードバック思想を再利用する。

- 正式結果が実際に変わった画面だけ通知対象
- 初回訪問だけ強調
- 再訪問時は通常表示
- OSの「動きを減らす」対応を維持

予定費一覧の追加・編集行を光らせる等の新しい演出はStep 11では追加しない。

---

## 22. 入力エラー

保存不可条件：

### 項目名

- 空欄
- 空白のみ
- 前後空白除去後に空
- 40文字超

例：

「項目名を入力してください」

等の平易な日本語で表示する。

### 予定年月

新規・通常保存時に、

- referenceMonthより前
- 保有目標年月より後

は保存不可。

### 金額

- 空欄
- 負数
- 小数
- 数値として解釈不能
- 1,000,000,001円以上

は保存不可。

0円は保存可能。

内部ルールをそのまま技術表記でユーザーへ見せない。

---

## 23. Golden Sample

初期Golden Sample自体は変更しない。

何も編集していない初期状態では、Step 9の正式値：

- 予定費のみ：11,341円/月
- 大型修理込み：29,808円/月
- 大型修理への備え分：18,467円/月

を維持する。

Step 11操作後にユーザーの予定費変更によって値が変化することは正常。

---

## 24. 既存仕様の回帰

Step 11実装によって、少なくとも以下を壊さないこと。

- Step 7の一覧表示仕様
- Step 8の10年間仕様
- Step 8のreferenceMonth基準
- Step 8の走行距離計算
- Step 9の既存計算式
- Step 9の計算不能状態
- Step 10の6設定項目
- Step 10の編集中状態と正式状態の分離
- Step 10の最大再計算回数
- Step 10の更新フィードバック
- 現行Home表示
- Golden Sample
- Navigation構造

Home旧表示を復活させない。

SQLiteを導入しない。

新しい大規模状態管理ライブラリを導入しない。

---

## 25. 代表受入シナリオ

最低限、以下をテスト対象とする。

1. 正常な予定費追加
2. duplicate追加
3. 0円予定追加
4. 項目名空欄
5. 項目名40文字
6. 項目名41文字
7. 金額空欄
8. 金額0円
9. 金額1,000,000,000円
10. 金額1,000,000,001円
11. referenceMonth登録
12. 保有目標年月登録
13. 有効範囲外新規登録
14. 既存予定費編集
15. 編集後も同じID維持
16. 変更なし保存
17. 予定費1件削除
18. duplicateの片方だけ削除
19. 削除確認キャンセル
20. 保有目標短縮による範囲外化
21. 範囲外予定費の試算除外（数値的な確認は主として年間合計・Step 8で行い、Step 9の数値変化は必須としない。第14節参照）
22. 保有目標再延長による自動復帰
23. 範囲外予定費の編集画面表示
24. 範囲外予定費の削除
25. 範囲外年月のまま編集保存不可
26. 空一覧表示
27. 年間合計更新
28. Step 8反映
29. Step 9反映
30. 不要な再計算が発生しない
31. 戻る操作で編集破棄
32. 明示的な「編集」操作のみで編集画面へ遷移
33. 一覧スクロール操作だけでは編集画面へ遷移しない
34. 360 logical px
35. text scale 3.0
36. 金額ellipsisなし
37. Golden Sample回帰

---

## 26. 実機確認

Flutter実装完了後、Pixel 6aで最低限以下を確認する。

- 予定費追加
- 編集
- 削除
- duplicate
- 0円予定
- 範囲外表示
- 空一覧
- 長い項目名
- 大きい文字設定
- 金額表示
- Step 8への反映
- Step 9への反映
- 戻る操作で編集破棄
- 縦スクロール時に意図せず編集画面へ遷移しない
- 明示的な「編集」操作でのみ編集画面へ進める

実機スクリーンショットを取得する場合は既存運用ルールに従い、Repository外のTemp等へ保存し、管理対象ファイルを変更しない。

---

## 27. Step 11完了条件

以下をすべて満たすこと。

1. 新規予定費を追加できる
2. 既存予定費を編集できる
3. 既存予定費を物理削除できる
4. duplicateを個別管理できる
5. 年間合計が正しく更新される
6. Step 8へ正しく反映される
7. Step 9へ正しく反映される
8. 不要な再計算をしない
9. 保有期間外予定費を削除せず保持できる
10. 範囲外予定費が試算から除外される
11. 有効範囲へ戻れば自動的に再度試算対象になる
12. 入力境界値を正しく処理する
13. 360 logical pxで横スクロール不要
14. text scale 3.0でも重要情報が欠落しない
15. スクロール時の意図しない編集遷移を防止する
16. 既存Step 7～10の回帰テストが成功する
17. Golden Sample初期値を壊さない
18. Pixel 6a実機で主要操作を確認する
19. Claude Coworkによる独立read-onlyレビューでPASS、またはChatGPT Project Chatと塁さんが指摘内容を確認し、Blockerではなく次工程を妨げないと判断したPASS WITH COMMENTSを得る

---

## 28. 実装開始境界

Flutter実装は、塁さんから明示的な実装開始承認を受けた後に、本書の承認済みStep 11仕様の範囲で行う。

- package追加は事前承認を必要とする
- SQLiteは導入しない
- formatterによる無関係ファイル変更は行わない
- commitは塁さんの明示承認後のみ行う
- Step 11当時は、pushは明示指示がない限り行わない運用だった。現在のGit／GitHub運用は、正本である `docs/development_workflow.md` および `AGENTS.md` の現行ルールに従う
- Claude Coworkによる独立レビューはread-onlyで行う

---

## 29. 愛車表示名 Baseline

本節はStep 11までの仕様を継承し、single-car MVPの愛車表示名と専用編集導線を追加する。Step 10で対象外だった車両名編集を本節で正式に承認する。

### データと検証

- 既存の `Car.name` をユーザー向けの愛車表示名として正式利用する。
- 必須のnon-nullable `String`。自由入力とし、`displayName` は追加しない。
- 保存時に `trim()` で前後空白を除去し、内部空白は保持する。
- CR（`\r`）・LF（`\n`）・Tab（`\t`）を含む入力は保存不可とする。禁止文字の判定はtrim前の入力に対してdomain validationで行う。
- UIでは通常入力・貼り付けの双方でCR・LF・Tabを除去する。通常の半角・全角スペースは内部空白として保持する。
- 正規化後に空なら保存不可。文字数は `runes.length` で数え、40文字可、41文字不可とする。
- 正規化・検証はpure Dartで一元化し、UIと正式反映処理で共用する。文字数packageは追加しない。
- Golden Sampleの名前は `メルセデスAMG E53` とする。名前以外の入力値・計算結果は変更しない。

### Homeと編集

- Home上部は `Keep My Car`、愛車表示名、明示的な「愛車名を編集」、保有目標要約、大型修理への備え要約、既存更新案内、既存4導線の情報階層とする。
- HomeはNavigation hub＋現在計画の短い要約を維持する。追加情報は愛車名と編集導線のみとする。
- 車名表示自体は編集操作にしない。文字付きの「愛車名を編集」に十分なタップ領域を設ける。
- `lib/features/car/presentation/car_name_screen.dart` に1項目の専用画面を置く。タイトルは「愛車名を編集」、入力初期値は現在のCar.name、主操作は「保存」。削除操作は設けない。
- 入力中は正式Carを変更しない。AppBar戻る・Android戻る等は入力を破棄し、破棄確認ダイアログは設けない。
- 保存時にtrim、検証、正式値比較を行う。不正値では正式状態を変更しない。
- 正規化後に同じ名前ならCar変更・不要な状態更新・計算・pending変更・更新通知を行わずHomeへ戻る。
- 実際に変更された場合のみHomeで「愛車名を更新しました」と短く通知する。試算結果用pendingや画面輪郭強調として扱わない。

### 状態管理と既存仕様

- 現在CarはKeepMyCarApp側で保持し、immutableを維持する。name・currentMileageKm・annualMileageKm更新に小さなcopyWithを用いる。
- PlanSessionにはCar全体を持たせない。正式試算条件・予定費・Step 8/9結果・pending等の既存責務を維持する。
- HomeにはAppから現在Carを渡す。車名変更はStep 8/9の再計算を行わず、既存pending・差額情報を保持する。
- PlanConditionsは既存6条件のままとし、愛車名を追加しない。
- 計算の走行距離SSOTはPlanConditions。計画設定の正常な正式反映時に、AppがCarのcurrentMileageKm・annualMileageKmも同じ値へ同期する。不正入力では同期しない。
- mileageCheckedMonth・firstRegistrationMonthは維持する。走行距離確認月の新しい更新ルールや独立した年式フィールドは追加しない。
- Step 8/9計算、Step 10の6条件の意味、Step 11 CRUD、既存Navigation構造、Japanese Locale、display formatting、Theme・fontは変更しない。
- HomeDisplayDataは復活・削除しない。旧固定金額・残り期間・目標時点車齢・目標時点走行距離等の旧Home表示は戻さない。
- 永続化・SQLite・クラウド・複数車・車両マスタ・メーカー等の分割・車両API・新状態管理ライブラリは追加しない。

### UI制約と受入条件

- 360 logical px、text scale 3.0で横スクロール不要、重要情報欠落なしとする。
- 愛車名は40文字でも折り返し可能とし、固定高さ・1行限定・ellipsisを使用しない。既存の縦スクロールを利用する。
- データとしての改行は禁止するが、表示幅に応じた自動折り返しは許可する。長い愛車名は縦方向へ拡張して全文を表示する。
- 編集画面は大きい文字・キーボード表示中でも入力欄、検証エラー、保存操作へ到達可能とする。
- Model検証：名前更新時の元Car不変・他フィールド維持、走行距離更新時の名前・年月保持。
- Validation検証：正常、1・40・41文字、空欄、半角／全角空白、trim、内部空白、Unicodeのrunes基準。
- Validation検証：CR、LF、Tabを含む入力はそれぞれ保存不可とし、前後に含まれる場合もtrimで見逃さない。通常の半角・全角の内部スペースは保存可能とする。
- Home／Editor検証：初期名・更新名、明示的編集、現在値、正常／trim保存、不正入力、変更なし、両戻る操作による破棄、通知、長い名前・大文字・キーボード、旧Home非復活。
- Editor／UI検証：通常入力・貼り付けの双方でCR・LF・Tabを正式値へ残さず、長い愛車名の自動折り返しを維持する。
- 状態検証：名前変更時のStep 8/9計算0回、pending・差額保持、計画設定からの走行距離2項目同期、mileageCheckedMonth維持。
- Golden Sample回帰：名前以外の入力値、Step 8の10年間と既存結果、Step 9の11,341円/月・29,808円/月・18,467円/月を維持する。
- 実装後は対象箇所のdart format、flutter analyze、既存＋追加の全flutter test、git diff --checkを実施する。
- Pixel 6aでは初期表示、編集、保存、変更なし、戻る破棄、40文字、検証エラー、大きい文字、キーボード、横overflowなしを確認する。
