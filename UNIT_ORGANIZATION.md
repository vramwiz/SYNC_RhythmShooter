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
