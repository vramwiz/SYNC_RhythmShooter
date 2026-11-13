## 2026-11-13 初見殺しアクション完成版の構成とコメント整備

本人の「これで完成」を受け、初見殺しアクションの計画v19を完成版として整理した。全147ユニットの最大は `RhythmBreakoutScore` の1442行。1500行超過、依存循環、フィールド宣言順の違反、責務ヘッダーの欠落はすべて0件。既存の7ユニットで責務が分かれており、今回さらに分割する必要はない。

| ユニット | 行数 | 担当 |
|---|---:|---|
| `TrapAction/RhythmTrapPlan` | 651 | 保存型、絶対時刻の軌道・支持・接触幾何、描画用カメラ位置 |
| `TrapAction/RhythmTrapBuild` | 818 | 全曲での57種類の採用・地形統合、速度・支持・回避距離の検証 |
| `TrapAction/RhythmTrapGimmicks` | 393 | 一つの連動する仕掛けに必要な音時刻と局所地形の組立 |
| `TrapAction/RhythmTrapCodec` | 106 | binary64の保存・復元、参照・版・音声条件の照合 |
| `TrapAction/RhythmTrapArt` | 474 | 保存された幾何・カメラを使った洞窟・罠・主人公・地上の描画 |
| `TrapAction/RhythmTrapScene` | 37 | 計画の所有、音声の借用、復元結果と失敗の保持 |
| `TrapAction/RhythmTrapStyle` | 38 | 共通準備・保存・描画窓口への接続 |

今後も1500行前後を分割判断の目安とする。近づいた場合は生成・検証・仕掛け群・描画・保存などの責務で分け、複数命令を一行へ詰めたり必要なコメントを削ったりして行数だけを減らさない。小さいScene/Styleの窓口はまとめず、既存の依存方向を保つ。

既存のコメントルールに従い、ユニット先頭の担当範囲、公開APIの所有権・前提・I/O、世界座標と原音声秒、床動作ごとに意味が異なる保存値、原音声長と追加演出終端の違いを補足した。Sceneの復元失敗を保持する理由、共通花火の二重描画を抑える理由、EQ合成の画素形式・明るさ保持の契約も記載した。処理の言い換えや重複コメントは増やしていない。

全147ユニットでコメント・空白を除く実行トークンが開始時と一致。フィールド・保存ID・計画v19・動作・配色・カメラ・ビルド設定は変更していない。日本語PascalはUTF-8 BOM/CRLFを維持。コメントと記録のみの変更なので再ビルド・再配備・試験EXE実行は行わず、直前に配備した完成版を保持した。AUP2/DPROJと配備済みAUF2/PreviewのSHA256も開始時と一致。構造一覧・比較結果は `Win64/TrapAction-complete-structure.json` と `Win64/TrapAction-complete-comments-audit.json`。

以下は各作業時点の記録。

---

## 2026-11-11 からくりリレーの分割とソースフォルダの整理

`Source` の137ユニットを確認した。最長は `RhythmBreakoutScore` の1442行で、各フォルダ直下は最多7ユニット。からくりリレーは既存の `RhythmMarblePlan` を接触候補の選択と保存・復元の窓口として使い、実装を次の単位に分けた。

| ユニット | 行数 | 担当 |
|---|---:|---|
| `RhythmMarblePlan` | 295 | 採用音の選択、譜面と音声情報の保存・復元、既存の公開型への参照 |
| `Planning/RhythmMarbleCourse` | 1026 | コースの型、絶対時刻からの位置・回転・接触・カメラの計算 |
| `Planning/RhythmMarbleLayout` | 665 | 主球のコース配置、レールの干渉確認、回転と描画区画の索引 |
| `Planning/RhythmMarbleLinkage` | 1085 | 2球と仕掛けの連鎖、通過時刻と画角の検証 |
| `RhythmMarbleScene` | 1412 | 背景、コース、球と仕掛けの描画 |
| `RhythmMarbleImages` | 124 | 材質と回転位相ごとの球画像の生成 |

`RhythmGame` は `Orbit`、`Orbit/Render`、`Legacy`、`Step` へ配置した。ブロック崩しの譜面は `Breakout/Score`、共通の表示と合成は `Composition/Presentation`、シューティングの画像生成は `Shooting/Assets` へ移した。製品・プレビュー・ビルドスクリプトの参照先も更新した。

`note.md` のコメント方針に沿い、ユニットの責務、公開入口の入出力と所有権、レコードの時刻・座標・速度の意味を記載した。構造検査で依存循環、宣言順の違反、1500行超過はいずれも0件。移動した22ユニットの内容、からくりリレーの179ルーチンの実装トークンと型のフィールド順を照合した。

全7製品のDLLとプレビューをDebug・Releaseで計28構成ビルドした。からくりリレーの保存譜面、試写540フレーム、外観見本10枚を整理前後で照合し、バイト単位で一致した。全15スタイルの実DLLでPCMなしの復元、プレビューとの描画一致、逆順シークをDebug・Releaseともに確認した。検証ログは `Win64/UnitOrganizationVerification`。

---

## 2026-11-04：共通描画時刻

RhythmTimingを追加し、解析と独立した秒オフセットを純粋関数へ分離。RhythmSceneの入口で全種類/EQ/カメラへ同じ補正を一度だけ適用する。ホストとPreviewの呼出側は秒値を渡し、個別Scene/Planや登録は変更しない。全115ユニット、最大1442行、循環・フィールド順違反0。所有/借用・符号・開始前透明・ホストtrackとPreviewコピーの正をコメント。全30ビルドと各構成288オフセット実描画比較が成功。HOST_TIMING.md参照。以下は過去時点の記録。

## 2026-11-04：種類カタログと専用アダプター

設定画面の種類選択を大・中・小の3段に整理。ピンボールとブロック崩しをボールアクションへまとめ、宇宙シューティングの縦／横を小分類へ配置した。12種類の生成・準備・保存後読戻し・PCMなし復元・描画接続を専用アダプターへ移し、RhythmStyleRegistryの登録表から一括で分岐する。

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

各種類は既存ディレクトリの専用Styleユニット（29〜51行）へ接続処理を分離。共通契約・登録・選択モデルを含め15ユニット追加、全114ユニット。最大1442行、循環・フィールド順・1500行超0。目的・所有・キャンセル・保存契約をコメント。詳細と全12対応表はSTYLE_CATALOG.md。全30ビルド、各構成2,638分類照合と実DLL192/228照合、全12種15PNG開始時不変。以下は過去時点の記録。

## 2026-11-04：MV重ねの一種類へ整理

音ゲーをMVへ重ねる単独種類へ戻し、種類リストは従来11＋リズムゲームの12種。前面／中層専用UI、別種類の同時描画・二重準備を撤去。黒背景を省き、黒い不透明記号・半透明の光を保つ乗算済みRGBAと透明余白を出力。Previewは同じRGBAを市松背景へ合成。共通EQは白文字チェックでON/OFFでき、表示だけの変更で計画は無効化しない。

| ユニット | 行数 |
|---|---:|
| RhythmOverlay | 81 |
| RhythmScene | 142 |
| RhythmPrepare | 342 |
| RhythmSettings | 217 |
| RhythmLayerBlend | 67 |
| RhythmPresentation | 41 |

旧RhythmLayerDataは製品usesから除外してTests/Supportへ移動。RhythmOverlayにalpha復元・透明変換・Previewを分離し、RhythmLayerBlendは一種類の共通EQ用の背景合成に限定。全99ユニット、最大1442行、循環・宣言順・1500行超過なし。目的・所有・alpha契約・透明余白・旧JSON移行の理由をコメント。以下は過去時点の記録。

## 2026-11-04 三層合成と表示部品

99ユニット、最大1442行。新規部品を音反応／所有窓口／中層データ復元／画素合成／音ゲー記号へ分離し、RhythmSceneを三層の制御窓口にする。各スタイルは通常背景の直後に背景抽出専用パスを設け、単独の演出・物理計画は変更しない。RhythmPrepareは共通Audioで二計画を準備／読戻し検証。新オプションはSettingsへ保存し、ホストとPreviewの共通Rendererへ渡す。

| ユニット | 行数 |
|---|---:|
| RhythmLayerBlend | 84 |
| RhythmOrbitMarks | 68 |
| RhythmEqualizer | 58 |
| RhythmLayerData | 46 |
| RhythmPresentation | 38 |

目的・所有／借用・二色マット・背景抽出・alpha・上限・計画と表示の独立をコメント。全30ビルド、各構成11中層229照合・全12実DLL・98描画比較、元11種14PNG不変を確認。循環参照／宣言順／1500行超過なし。THREE_LAYER_COMPOSITION.mdとVerification/OrbitPresentation-20261104/handoff.json参照。以下は過去時点の記録。

---

## 2026-11-04 宇宙軌道v3の解析と演出を分離

全94ユニット、最大1442行。Game専用の細粒度候補抽出／重複・品質をRhythmOrbitAudio、導入／ゲート／クリア描画をRhythmOrbitShowへ分離。共通音解析は変更せず、GamePlanが一時スナップショットを作りPlanへ渡す。Codecはv2/v3を区別し、元音声と専用イベント数が違うv3もPCMなしで復元。保存曲線と時刻を描画が参照し、再生履歴を持たない。

| ユニット | 行数 |
|---|---:|
| RhythmOrbitPlan | 281 |
| RhythmOrbitScene | 253 |
| RhythmOrbitAudio | 145 |
| RhythmOrbitCodec | 116 |
| RhythmOrbitShow | 72 |

全製品／Previewに明示登録。循環参照／宣言順違反／1500行超過なし。最終30ビルドと密度／計画／描画／旧版／全12実DLL回帰、本人AUP2と他11種の不変を確認。RHYTHM_GAME_STYLE.mdとVerification/OrbitFinale-20261104/handoff.json参照。以下は過去時点の記録。

---

## 2026-11-04 未来ガイドの読み取りを分離

現在は92ユニット、最大1442行。新規RhythmOrbitGuideは保存済みの実移動の未来サンプル、時間窓の密度/強度/反応を純粋な関数で読む。OrbitSceneはその結果を連続線/階層付き予告/背景へ描く。計画、採用音、カメラ、最低強度、Codecは変更しない。全製品/PreviewへGuideを明示登録。全30ビルド、両構成Guideと宇宙17入力、全12実DLL、旧11種14画像/保存v2計画18個の不変を確認。以下は各時点の構成記録。最新詳細はVerification/OrbitGuide-20261104/handoff.json。

---

## 2026-11-04 宇宙リズムv2の責務分離

現在は全12スタイル・91ユニット、最大1442行。RhythmGamePlan/Sceneはv2/v1の切替窓口へ変更。新規RhythmOrbitTypes（世界座標/保存型/純粋曲線）、RhythmOrbitPlan（採用/周回/飛行/連続カメラ）、RhythmOrbitCodec（binary64保存と復元）、RhythmOrbitScene（宇宙描画）へ分離し、旧v1はRhythmGameLegacyPlan/Sceneに保持した。新製品や列挙は増やさず、既存11スタイルの演出・保存版・識別順を維持。全製品/Previewへ明示登録。最低強度の状態は共通Settings/UIに置き、音声解析自体は既存経路を使う。

循環参照・宣言順違反・1500行超過なし。全30ビルドと両構成の全12実DLL照合、17入力の世界位置/音時刻/カメラ/強度/v1互換試験を通過。以下は各時点の構成記録で、その時点の行数・総数を含む。最新詳細はRHYTHM_GAME_STYLE.mdとVerification/OrbitGame-20261103/handoff.json。

---

## 2026-11-03 リズムゲーム風の追加

現在は全12スタイル・85ユニット、最大1442行。新規 RhythmGamePlan（302行）は全曲計画・絶対時刻の位置・保存検証、RhythmGameScene（162行）は判定マーク/軌道/カーソル/接触演出を担当。新規スタイルIDを列挙末尾へ追加し、既存の識別順・JSON版・演出は維持する。共通Prepare/Scene/Host/Settingsは新スタイルへの委譲を追加。既存全製品とPreviewにユニットを明示登録し、新SYNC_RhythmGame製品・Previewを追加した。GUIや配備は行わない。

全12 DLL両構成24ビルド＋代表Preview6コンパイル、各構成12実DLLの描画/ホスト音楽入力/PCMなし復元/seekを通過。旧14PNGは開始コミットを同条件で再コンパイルした画像と一致。詳細は [RHYTHM_GAME_STYLE.md](RHYTHM_GAME_STYLE.md) と Verification/RhythmGame-20261103/handoff.json。以下は2026-11-02の構造整理時点の記録であり、そこでの版・行数・総数は当時の値。

---

# ユニット構成と整理結果（2026-11-02）

Race v9の修正を保存・ビルド・試験した後、その状態を基準に構造だけを整理した。比較基準は Verification/RaceTruck-20261102/before-refactor.json。既存の呼出窓口と保存型名は薄い委譲や型エイリアスで保持し、計算実装は重複させない。

| 対象 | 元の窓口 | 分離先 | 整理後の行数（窓口／分離先） | 目的 |
|---|---|---|---|---|
| 音声 | RhythmAudio | RhythmAudioData / RhythmAudioCache / RhythmAudioDecode | 89 / 150 / 170 / 79 | 既存APIは窓口で維持。データ・ディスク復元・準備時デコードを分離。 |
| Ball | RhythmBallScene | RhythmBallCircuitScene / RhythmBallLegacyScene | 60 / 198 / 185 | 現行v6と旧v4/v5の描画を分離。 |
| Runner | RhythmRunnerScene / RhythmRunnerAction | RhythmRunnerPixels / RhythmRunnerLegacyScene | 60 / 336 / 651 | v6と旧1～5を分離。計画から描画依存を除き、Pixels入口を型付きに。 |
| Fighting | RhythmFightingScene | RhythmFightingDuelScene / RhythmFightingLegacyScene | 59 / 228 / 373 | 現行v2と旧v1の描画を分離。攻防・顔・腕の動作は保持。 |
| Race | RhythmRaceCrash | RhythmRaceCrashMotion / RhythmRaceCrashBuild / RhythmRaceCrashCodec / RhythmRaceTrafficContacts | 55 / 404 / 312 / 307 / 260 | 窓口／絶対時刻位置／逆算生成／保存・前向き検証／交通接触を分離。 |
| Breakout | RhythmBreakoutScore | RhythmBreakoutScoreTypes / RhythmBreakoutScoreGeometry | 1442 / 46 / 448 | 保存契約と独立した曲線・矩形の連続分離検証を分離。 |

全81ユニット、最大1442行（RhythmBreakoutScore）。1500行目安を超えるユニットはなく、例外扱いは不要。元の複数命令1行を分行したため、単純な行数の増減ではなく責務と読める長さを基準にした。46行のScoreTypesはプランと幾何検証が共有する保存契約であり、循環参照を作らないための分離。

## 全11スタイル

| スタイル | 計画／描画の境界と保存互換 |
|---|---|
| Shooting | ShootingScene、Stage、Sections、Barrage、Motion。既存の責務分離を維持、計画v1。 |
| Ball | BallPlan／CircuitPlan、現行CircuitSceneとLegacyScene。現行6、旧4～5読込。 |
| Fireworks | FireworksPlan／FireworksScene。現行3、旧2読込。小さいユニットは増分割しない。 |
| Runner | RunnerPlan／Action、PixelsとLegacyScene。現行7、旧1～6読込。 |
| Breakout | Plan／Campaign／Score／ActionとScene。Scoreの型・幾何検証を別ユニット化。現行10、旧1～9読込。 |
| Race | 旧1～7のPlan／道路・HUDと、8～9のCrash系を分離。現行9、旧1～8読込。 |
| BombAction | BombPlan／BombSceneを維持。現行2、旧1読込。 |
| Fighting | FightingPlan／Duel、DuelSceneとLegacyScene。現行2、旧1読込。 |
| Mining | MiningPlan／MiningSceneを維持。現行1。 |
| Train | TrainPlan／TrainSceneを維持。現行1。 |
| Naval | NavalPlan／NavalSceneを維持。現行1。 |

全11製品のDPR/DPROJと全11 PreviewのDPRへ版別ユニットを明示登録した。GUID、出力／配備設定、SDKの型・アラインメントは変更しない。音楽入力は既存の [HOST_MUSIC_INPUT.md](HOST_MUSIC_INPUT.md) を維持。

## コメントと宣言

note.mdの既存方針に従い、目的・責務・重要な副作用・値の意味を補う。自作ユニットの先頭に担当範囲、分離した公開入口に所有権や前提を記載。音時刻を動かさない理由、逆算の順序、連続分離の根拠、撃破後の再出現防止をコメント化した。処理の逐語説明や重複コメントは増やさない。

フィールドはメソッド宣言より前に配置し、既存の公開範囲とフィールドの記憶順序を保持。SettingsFormのDFMイベントは明示publishedとして名前解決を保持し、フォーム生成なしのRTTI試験で確認。日本語Pascal/DPRはUTF-8 BOM、改行CRLF。SDK／Libは変更しない。

Scripts/VerifyUnitStructure.cjs は読み取り専用。依存循環、フィールド順、目的コメント、行数を検査する。実行トークンを比較して分行・字下げによるコード改変を防いだ。古いJS数値モデルは過去版の記録として保持し、現行Race v9の受入はRacePlanSmokeを使う。

## 検証

- 最終宣言整理後、全11 DLL Debug／Release計22ビルドとShooter／Race Previewの両構成計4コンパイルに成功。非配備のWin64/Localへ出力。
- 最終ソースの実DLLは各構成で全11種、音楽入力状態176件、GDI／D2D・PCMなし復元・乱順seek176件を通過。DLLと共通Preview描画のピクセル一致を確認。
- 整理前後の14 PNGと39保存計画がバイト一致。61既存ユニットの実装部もコメント・空白を除いたトークンが一致。
- 専用コンソール試験11件（AudioEdges、AnimationArchitecture、BallPlan、BallCircuit、Fireworks、BreakoutPlan、BreakoutAction、Runner、Fighting、Race Debug／Release）を通過。宣言順の最終整理では記憶順を保持し、追加RTTI確認と最終の全製品／実DLL照合を実施。
- 実WAVの4アクセント、同パス上書き、無音、無効MP3、PCMあり／なしキャッシュ復元を確認。再生はしない。
- GUI試験はコンパイルのみ。Runner確認EXEへの既存出力先でF2039となったため、NativeTests/RefactorCompile内の別専用先へコンパイル成功。既存EXEの上書き・停止・GUI操作は行わない。

既存Breakout試験の古いRunner版期待値と、過去検証フォルダへ直接出力していた2試験の保存先を修正した。製品動作の変更ではなく試験整備。GUI／実AviUtl2／音付き連続動画は未確認。配備・commit/pushなし。証跡は [引継](Verification/RaceTruck-20261102/handoff.json)。
