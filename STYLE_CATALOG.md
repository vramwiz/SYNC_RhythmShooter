# バリエーション分類と共通ディスパッチ

2026-11-05 / 選択できるバリエーションは13種類。トロッコアクションは列車と別に選べる。花火は共通のゴール演出。後半の検証記録は当時の構成。

設定画面の種類選択を大・中・小の3段に整理。ピンボールとブロック崩しをボールアクションへまとめ、宇宙シューティングの縦／横を小分類へ配置した。各種類の生成・準備・保存後読戻し・PCMなし復元・描画接続を専用アダプターへ移し、RhythmStyleRegistryの登録表から一括で分岐する。

## 設定画面の分類

| 大分類 | 中分類 | 小分類・視点 |
|---|---|---|
| シューティング | 宇宙シューティング | 縦スクロール／横スクロール |
| シューティング | 装甲列車 | 横からの視点（固定） |
| シューティング | 海戦 | 見下ろし（固定） |
| ボールアクション | ピンボール | 縦スクロール／横スクロール |
| ボールアクション | ブロック崩し | 固定盤面 |
| アクション | ジャンプアドベンチャー | 横・縦の自動切替 |
| アクション | 爆弾アクション | 見下ろし（固定） |
| アクション | 格闘ラッシュ | 地上戦・空中戦 |
| アクション | 掘削アクション | 見下ろし（固定） |
| アクション | トロッコアクション | 鉱山の横スクロール |
| レース | 2Dハイウェイ | 横スクロール（固定） |
| 音楽・演出 | Type.V | MV重ね（透過） |
| 音楽・演出 | Type.D | 縦 |

小分類が1つの種類では説明を表示して選択を無効化する。ピンボールの2方向は元のdirectionの意味を保持する。分類変更後は先頭の中分類へ切り替え、実際の種類変更時だけ方向を0へ戻す。同じ分類・種類を選び直しても元の方向を保つ。大→中→小の操作は500ms待機し、ドロップダウンが開いている間は準備を待たせる。

## 分類の考え方と公式資料

分類はこのアプリの実際の遊戯表現に合わせた設定上の整理で、業界共通の唯一の分類を主張するものではない。

- ボール反射を主体とするピンボール／ブロック崩しを同じ大分類へ。[任天堂ストアのジービー](https://store-jp.nintendo.com/list/software/D70010000104509.html)は両要素を持つ公式の実例。
- シューティングの縦／横はゲームジャンルの別列挙にせず視点の小分類へ。[任天堂の沙羅曼蛇紹介](https://www.nintendo.com/jp/topics/article/890c8deb-ebd8-405b-b14f-08ce42a90730)に両スクロールの公式説明がある。列車と海戦は当リポジトリの砲撃・迎撃中心の内容を基準に同じ大分類へ置く。
- 爆弾・格闘・掘削・足場ジャンプをアクションへ。[コナミのボンバーマン公式](https://www.konami.com/games/bomberman/collection/jp/ja/)も爆弾アクションの参考とした。
- レースは車両走行、音楽・演出はリズムゲーム。[バンダイナムコの公式ジャンル一覧](https://www.bandainamcoent.co.jp/license/detail3/)のリズムゲームという種類を参照。

## 責務と登録の境界

`RhythmStyles`は保存契約を含む低層のカタログ。表示名・分類順・対応機能・計画互換版を1表に持ち、各Planからも参照できる。`RhythmStyleSelection`はフォームに依存しない選択状態を扱う。

実装への分岐は`RhythmStyleRegistry.Factories`の1表。各種の専用`*Style`ユニットが同じ`TStyleOperations`契約を提供し、Renderer・Prepare・ホストの冷復元から共通に呼ぶ。UIの分類だけに依存するカタログと、Scene/Plan実装に依存する実行登録を層で分けることで、Plan→カタログ→Planの循環を防ぐ。各窓口に12種の型castやcaseを複製しない。既存互換関数PlayerAt等のshooting委譲は残す。

`TStylePrepareContext.Audio`は準備スレッドの借用。キャンセルと進捗はコールバックで元の段階を保つ。アダプターは元のBuild/Save/読戻しとsummaryを移設し、音時刻・計画形式・描画本体を変更しない。Scene/Imagesは新規所有物として生成し、Renderer/Presentationへ所有権を渡す。設定フォームに種類固有クラスを持たせない。Activity/Transparencyは必要な種類だけの任意フック。

| 共通ユニット | 行数 | 場所 |
|---|---:|---|
| `RhythmStyles` | 108 | `Source/Shared/Settings/RhythmStyles.pas` |
| `RhythmStyleSelection` | 37 | `Source/Shared/Settings/RhythmStyleSelection.pas` |
| `RhythmStyleOps` | 42 | `Source/Composition/RhythmStyleOps.pas` |
| `RhythmStyleRegistry` | 34 | `Source/Composition/RhythmStyleRegistry.pas` |
| `RhythmPrepare` | 102 | `Source/Composition/RhythmPrepare.pas` |
| `RhythmScene` | 120 | `Source/Composition/RhythmScene.pas` |
| `RhythmPresentation` | 40 | `Source/Composition/RhythmPresentation.pas` |
| `SYNC_RhythmShooter_SettingsForm` | 1225 | `Source/Shared/Host/SYNC_RhythmShooter_SettingsForm.pas` |
| `SYNC_RhythmShooter_FilterPlugin` | 456 | `Source/Shared/Host/SYNC_RhythmShooter_FilterPlugin.pas` |

| 保存enum | 専用接続ユニット | 行数 |
|---|---|---:|
| `rsShooting` | `Source/Shooting/RhythmShootingStyle.pas` | 29 |
| `rsBall` | `Source/Ball/RhythmBallStyle.pas` | 43 |
| `rsJumpAdventure` | `Source/JumpAdventure/RhythmJumpStyle.pas` | 74 |
| `rsBreakout` | `Source/Breakout/RhythmBreakoutStyle.pas` | 51 |
| `rsSideRace` | `Source/SideRace/RhythmSideRaceStyle.pas` | 72 |
| `rsBombAction` | `Source/BombAction/RhythmBombActionStyle.pas` | 45 |
| `rsFightingRush` | `Source/FightingRush/RhythmRushStyle.pas` | 70 |
| `rsMining` | `Source/Mining/RhythmMiningStyle.pas` | 45 |
| `rsTrain` | `Source/Train/RhythmTrainStyle.pas` | 45 |
| `rsNaval` | `Source/Naval/RhythmNavalStyle.pas` | 45 |
| `rsRhythmGame` | `Source/RhythmGame/RhythmGameStyle.pas` | 46 |
| `rsStepGame` | `Source/RhythmGame/RhythmStepStyle.pas` | 80 |
| `rsMineCart` | `Source/MineCart/RhythmCartStyle.pas` | 68 |

全114ユニット、最大1442行、1500行超・循環・フィールド宣言順違反は0。新しい15ユニットは目的ヘッダーとUTF8 BOM/CRLFを統一。目的・所有／借用・分類値を保存しない理由・固定direction維持・キャンセル・音ゲー専用反応のフォールバックをコメントし、既存の個別計画/描画コメントは保持。

## 種類を追加するとき

1. 既存enum/IDを並べ替えず、RhythmStyles末尾へID・計画互換版・分類/機能を追加する。
2. その種類の専用ディレクトリにScene/PlanとStyleアダプターを配置する。大きい描画・物理・codecは責務で分ける。
3. 必須6操作を実装し、RhythmStyleRegistryのFactoriesに1行を登録する。描画/準備/冷復元の呼出側へcaseを追加しない。
4. カタログ試験のID/版契約と実DLL統合試験へ追加し、全既存種類の描画・旧保存復元を比較する。

## 互換性・検証・利用

分類名・分類indexは保存せず、既存のstyle ID・enum順・direction 0/1・各計画版・variant・cache keyを保持。分類用のAviUtl2パラメータは追加しない。旧保存から大中小を逆引きし、固定視点の旧direction値も勝手に変更しない。リズムゲームは音楽・演出→リズムゲーム→MV重ね（透過）の一種類のまま。共通EQのON/OFFと白文字チェックも維持する。

全12DLLのDebug/Release24構成と、Game/Shooter/Race Previewの両構成6、計30ビルド成功。各構成で分類・保存ID/版/recipe・機能登録・復元2,638照合／360選択遷移、実DLL12種の192 warm/cold/seek・228ホスト音楽/EQ照合を通過。MV用5入力と旧v1/v2で18,663,060画素等の照合／24画像、マーク342照合／14画像、音解析11入力385照合も通過。38PNGがDebug/Release一致、開始時の全12種15PNGも両構成で完全一致。

既存99ソースのうち93本はバイト単位で不変。変更6本は共通窓口・カタログ・フォームだけ。本人AUP2・Assets・SDK・ThirdPartyは開始時ハッシュと一致。検証証跡は`Verification/StyleCatalog-20261104/{handoff.json,scope-checks.json,source-final.json,adapter-extraction.json,Final/}`。抽出時の元/新コードと最終ソースを照合して準備処理の等価性も確認した。

新DLLを本人側で反映後、設定画面で大→中→必要なら小を選ぶ。同じ既存style/directionの復元だけなら再準備不要。実際に種類・方向・音源・解析値を変えたときは従来どおり準備→適用→AUP2保存。分類だけのホストパラメータ設定は不要。

Computer Use・GUI操作・配備・commit/pushは実施していない。新分類画面の実配置・DPI/文字切れ・実AviUtl2操作と実音は未確認。SettingsLayoutSmokeは両構成コンパイルのみ、SettingsRttiSmokeはフォーム生成なしで成功。Escapeで停止した画面にも触れていない。


## 2026-11-04：ホスト項目の追加整理

旧スクロール方向（小分類）/解析感度のホスト項目も撤去し、設定画面→JSONを唯一の入力とした。分類とは別に描画用の秒オフセットをホストへ追加。既存分類ID/方向の意味を保持し、オフセットだけでは計画を変更しない。旧JSONなしの移行制約を含めHOST_TIMING.md参照。

## 2026-11-04 4レーン・リズムと音要素の感度

追加時の4レーン演出は現在のType.D。下から流れるノートの1～4本の斜線がレーンを示す。検出した音の時刻で判定線が発光し、強い音は2列が同時に反応する。幅280px以上かつ横縦比1.42以上は2人分の異なるレーン割当を横に並べ、それ以外では1人分を表示する。譜面は自動演出で、入力操作を要求しない。追加時は全画面背景付きで描画し、共通EQとホストの描画オフセットも使える。

音源の「解析感度」と、検出後にどの音を採用するかを決める「音要素の感度」を全13種類で表示する。音要素は−100～100で、左ほど細かな音を追加し、右ほど強い音に絞る。従来の非音ゲーは20で旧選択を維持し、追加音にのみ既存音・他の追加音との180ms間隔を適用する。2種類のリズムゲームは短い音間隔にも対応する。変更後は準備して適用する。

新しい保存IDは `prism-step`、計画はv1。時刻と左右のレーン割当を保存してPCMなしで復元する。共通の感度は設定JSONの `audioDensity` へ保存し、旧リズムゲームの `gameThreshold` も読める。既存のスタイルID・計画版・標準密度の計画キーを維持する。シューティングの標準以外の密度は、選抜済みの音イベントを準備済みデータへ保存する。

## Type.D v3

「音楽・演出 → Type.D → 縦」で選択する。横長は左右2人分、それ以外は1人分を表示する。判定線、HITS、レーンの斜線、見出しと進行表示を残し、レーン周辺のみ半透明でMVに重ねる。ホストのオフセット、EQ、位置と拡大の既存設定を使用する。

実ピークをその時刻のまま通常、連打、左右連続、同時押し、ロング、スライドへ振り分ける。連打は同じ列、左右連続は4打または7打の往復、スライドは隣接する2つの採用時刻を使う。ロングは採用した立ち上がりから周期音が続く場合に限り、離す時刻も譜面に保存する。v3は時刻、強度、左右のレーン、種別とロングの終了時刻を保存し、PCMなしで復元できる。v1・v2は従来の表示で開き、新しい演出には準備と適用が必要。
