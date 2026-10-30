最新追加: [RUNNER_STYLE.md](RUNNER_STYLE.md)。SYNC_RhythmRunner／ランナー（列挙値3）を追加。着地同期の放物線ジャンプ、飛び石/階段、有意音終了のゴールと右退場、保存計画からの復元をソース実装。敵踏みは未実装。今回未ビルド・未実行・無配備。

設定画面UIも更新: 音楽行の下をコンパクトな左キャプションの設定行へ整理、再生/一時停止トグル、波形クリックの即時シークを実装。詳細は [BALL_PERSISTENCE.md](BALL_PERSISTENCE.md) のUI節。今回未ビルド・未実行・無配備。

最新修正: [BALL_PERSISTENCE.md](BALL_PERSISTENCE.md)。ボールv5は保存済み計画から復元し、PCMキャッシュ依存を除去。旧v4互換あり。**ソース保存・静的確認のみで、今回変更後は未ビルド・未実行・無配備。実エラーの最初の発生分岐と再起動動作は未検証。**

最新更新: [TRAJECTORY_UPDATE_20261030.md](TRAJECTORY_UPDATE_20261030.md)。ピンボールv4の直線反射、花火v2の垂直打ち上げ・6種類・専用画面「華やかさ」をソース実装。**今回変更後は未ビルド・未実行・無配備。以前のビルド成功は変更前の履歴。**

最新のビルド確認: [BUILD_VERIFICATION_20261030.md](BUILD_VERIFICATION_20261030.md)（3製品×Win64 Debug/Release成功、実動作未確認）。

最新追加（未ビルド）: [FIREWORKS_STYLE.md](FIREWORKS_STYLE.md)。ボール高感度/適用保存の修正記録はBALL_STYLE.md末尾。

# SYNC_RhythmShooter 作業ノート

**最新は [BALL_STYLE.md](BALL_STYLE.md)（ボール別プロジェクトとスタイル切替、ソース実装済み・未ビルド）。構成は [ARCHITECTURE.md](ARCHITECTURE.md)。ビルドはユーザーが行う。**

**最新のソース構成は [ARCHITECTURE.md](ARCHITECTURE.md)（2026-10-30、責務分割後・未ビルド）を参照。ビルドはユーザーが行う。**

**機能の利用手順は[REVISION4.md](REVISION4.md)／[カスタムデザインの使い方](CUSTOM_DESIGN.md)。** 設定画面タイトルは Revision 4。15素材の個別設定と専用Codex連携を実装し、実AI生成・実GUI操作は未確認。以下の基本版記録は履歴として保持する。

## 現在のビルド設定（2026-10-28・クローン後の修正）

- 戦闘演出の更新：爆発は拡大しながらアルファを落として消す（通常0.60秒、ボス1.35秒＋遅延した小爆発）。D2DのopacityとGDIの乗算済みアルファで両経路に対応。撃破対象とは別に、射撃の命中列より上を横切る通常敵3種の編隊を追加し、後半ほど出現間隔と数を増やす。
- ボス区間：ユーザー指定により曲長に応じて増やす。音がある長さ÷45秒を目安に丸め、90秒で2戦・約175秒で4戦。8秒以下と無音はボスなし、短曲は1戦、末尾の無音は回数へ含めない。`RhythmSections.pas`でRMS包絡線の高い区間から静かになる境界を検出し、撃破時刻へ採用。見つからない区間は拍付近または音の終端へフォールバックする。各戦闘はおおむね20秒、最大23秒とし、重複させない。解析結果は音源ごとに保持し、毎フレーム解析しない。
- 弾幕は花弁→螺旋→扇状→交差状の4種類を順に使用し、さらに長い曲では循環。曲の進行・戦闘後半・音量に応じて弾数、発射間隔、速度を増強する。既定自機経路との危険な弾は発射前に除外し、撃破時は残弾も0.45秒で消す。通常射撃とボスの最後の射撃は従来の直進・命中逆算を維持する。
- 戦闘検証：`Scripts/TestCombat.cmd [任意の音楽パス]`で再実行。90秒合成曲の静かな境界31.90秒／75.00秒で撃破し、各約20秒の戦闘、終盤の密度・速度上昇、短曲・無音・末尾無音、爆発の実描画フェード、GDI/D2D両経路・縦横のシーク一致を確認。現在の実曲175.03秒では40.04／76.42／119.38／171.08秒の4戦（初戦のみ境界なしの拍フォールバック）。終盤1920×1080のD2D描画30回平均約6.31msはこのPCの単回測定で、実ホスト転送や音声を含まない。実曲の衝突回帰では最小自機距離約0.0649（予約半径0.065、許容下限0.054）、画面内最大約1396発を確認。証拠は`Win64/Debug/CombatVerification/combat-smoke.json`、`Win64/Debug/Verification/revision3-smoke.json`。
- 製品Debug／Releaseは警告0・エラー0。Releaseを既定フォルダーへ配置し、配備実体の必須export、描画・変形・欠損キャッシュ・初期化終了を`Tests/PluginSmoke.dpr`で確認した。最新の戦闘演出の実AviUtl2での通し再生は未確認。
- 暗色化・配置・プレビュー修正：`Source/UI/RhythmControls.pas`に画面専用のボタン・コンボ・スライダー描画とプレビュー面を追加。VCLの全体スタイルを切り替えず、本画面の配色とタイトルバーだけを暗色化する。上部は設定、中央は映像、下部は再生操作と時刻、最下部は状態と適用ボタンへ配置を統一。カスタムデザインも暗色に統一した。プレビューを背景消去しない不透明な二重バッファ付きウィンドウへ変更し、描画途中の消去表示を抑制。通常・曲終了後の左上のSYNC/時刻/accents/CLEARは非表示にし、未準備・素材欠損等の警告は保持する。この変更により旧HUDを含む画像ハッシュは意図的に変わる。
- 今回の検証：`Tests/SettingsLayoutSmoke.dpr`の192 DPI初期表示・96/144/192相当の拡縮・狭幅・両タブのナビゲーション、`Tests/SettingsFormSmoke.dpr`の生成と連続開閉、`Tests/PreviewRenderSmoke.dpr`の正常時テキスト非表示/警告保持と120フレーム連続描画・背景消去抑止を確認した。暗色の両タブを画像で確認。実ホストでの音楽再生中のちらつきは最終的に実機で確認する。
- 設定画面のDPI修正：DFMのフォント拡大後に動的コントロールへ96 DPIの固定座標を入れていたため、192 DPIでラベル・入力欄が重なることを再現。現在DPIで寸法・余白を換算し、アニメーション側の入力・操作欄はAlignを使う配置へ変更。初期サイズを作業領域内に収め、カスタムデザインの各行も同じ倍率で生成し、必要時は横スクロール可能とした。`Tests/SettingsLayoutSmoke.dpr`で192 DPI初期表示、96/144/192相当の拡縮と96へ戻す操作、論理幅1100/850の両タブを検証し、操作部品の重なり・親領域からのはみ出し・ボタン文字の欠けを確認。画像は`Win64/Debug/LayoutVerification`へ保存し、192 DPIの狭幅両タブと96 DPIの狭幅アニメーションを目視確認した。実際のモニター間移動は未確認。設定画面の生成・設定ボタン連続開閉テストも成功。
- 設定ボタンの生成順序修正：`TRhythmDesignFrame.Create`で親未設定のまま子コントロールを生成し、`EInvalidOperation: Control 'FrameRhythmDesign' has no parent window`になることを再現。子の生成を`SetParent`後へ移し、親接続前の設定値も接続時に反映する。`Tests/SettingsFormSmoke.dpr`で未接続フレームの生成・破棄、事前設定の保持、設定画面の両タブ描画、プラグインの設定ボタン経由で2回連続の表示・取消を確認した。テストはLOCALAPPDATAを`Win64/SettingsSmokeUserData`へ隔離し、音声・AI通信・設定保存を行わない。
- 作業場所は`V:\DelphiProg\SYNC_RhythmShooter`。同階層`SYNC_MusicStudio/SYNC_MusicStudio_Filter.dproj`と`Scripts/BuildPlugin.ps1`、`MapRaku/SYNC_MapRaku_Filter.dproj`を読み取り参照した。
- Delphi 37.0／Win64のDebug・Release両方に、IDEの前処理・後処理イベントを設定。`Scripts/BuildPlugin.ps1`が実DLLの`$(OUTPUTPATH)`を受け取り、同じ出力フォルダーへAUF2・Assets・ThirdPartyをそろえ、`C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter`へ配置する。DLLとDCUは作業フォルダーに保持する。
- `BT_BuildType`は両構成ともWin64テンプレートと同じ`Debug`。Releaseの最適化・デバッグ情報は`DCC_Optimize=true`、`DCC_DebugInformation=0`等で指定する。Debugはデバッグ情報・ローカルシンボルを明示する。
- デバッグのホストは両構成とも`D:\aviutl2_v2.1.6a\aviutl2.exe`。作業ディレクトリは同階層の他プロジェクトと同じく未設定とする。`DCC_ExeOutput`は`SYNC_MusicStudio`と同じ`.\$(Platform)\$(Config)`を直接指定し、IDEの出力先で独自MSBuildプロパティを参照しない。IDEで既に開いている場合は、外部編集したDPROJを再読込する。
- 初回クローンではGit管理外のFFmpegバイナリがないため、ビルド前に`Scripts\PrepareFFmpeg.ps1`を実行する。既存`provenance.json`に記録した固定URL・ZIPと各ファイルのSHA256を検証し、`ThirdParty\FFmpeg\bin`へ復元する。ローカルZIPは`-ArchivePath`でも指定できる。
- 通常ビルドは`Scripts\Build.ps1 -Config Debug`／`-Config Release`。プレビューも必要なら`-Tools`を追加する。前後処理の失敗はビルド失敗として扱う。ロック中ファイルの強制置換やアプリの強制終了は行わない。ユーザー画像の`DesignAssets`とユーザー設定はコピー対象外。
- 隔離ビルドはMSBuildへ`/p:RhythmDeployDirectory=`を渡して配備を無効化する。`Scripts\BuildRevision4.cmd`はこの指定を行う。出力の変更は標準の`DCC_ExeOutput`、DCU出力の変更は`DCC_DcuOutput`を使用する。
- 修正後のDebug・Releaseは警告0／エラー0。両構成のDLLとAUF2が一致し、Releaseの配備28ファイルも出力元とSHA256一致。既定Releaseの出力先変更・無配備ビルド、配置先ロック時の非0終了と配備ファイル不変を確認した。ログは`Win64/Debug.build.log`、`Release.build.log`、`BuildSettingCheck.build.log`、`DeploymentLocked.log`。IDE実画面・AviUtl2の起動確認は未実施。
- 実行設定の再比較：AIArtToPSD・MangaMaker・MimiCopyStudio・RIGMMaker・SYNC_MusicStudio・MapRakuのプロジェクトに有効な`Debugger_CWD`指定はなかった。MapRakuの`Debugger_WorkingDirectory`はDelphiの作業ディレクトリ欄へ反映されない項目であり、参考として追加したのは不適切だった。一時的な`Debugger_CWD`指定ではF9起動を確認したが、最終設定ではこの回避策を外し、独自`RhythmOutputRoot`を廃止して出力先を標準形式へそろえた。標準出力先へ変更後のDebug・ReleaseはMSBuildで警告0／エラー0（ログはWin64/StandardOutput.Debug.build.log・StandardOutput.Release.build.log）。作業ディレクトリ未設定の最終状態でのIDE起動と、プラグインの機能確認は別途必要。


## 目的と確定名称

音楽を指定して縦横を選ぶだけで、その曲専用の音ハメシューティング映像を自動生成するAviUtl2用フィルター。音楽から命中時刻を先に決め、発射と敵動作を逆算する。

- プロジェクト／DPR／出力名：`SYNC_RhythmShooter`
- グループ：`SYNC`
- 表示名：`リズムシューティング`
- 説明：`リズムシューティングフィルタープラグイン`

## 文書の入口

- [SPEC_SOURCE.md](SPEC_SOURCE.md)：受領仕様全文。原文は変更していない。
- [SPEC.md](SPEC.md)：確定名称・追加指示の差分、要件整理、未確定事項。
- [TASKS.md](TASKS.md)：完了範囲、残作業、保留事項。
- [BUILD_RESULTS.md](BUILD_RESULTS.md)：ビルド・指定曲・描画・音声時計検証と承認ブロック。
- [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)：ボス・弾幕・回避・音声等の機能別到達点と未実装範囲。
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)：参考元、FFmpeg同梱物、標準素材の由来。

## 現段階

最初の雛形コピー・名称設定・ビルド確認に続き、追加指示で約2時間の基本実装と実曲検証へ拡張された。専用設定画面の音楽付きプレビューは今回の確定要件。AI生成と未確定カスタマイズUIは保留する。

実装済みはWAV／MP3の全曲デコード、PCMディスクキャッシュ、立ち上がり検出、命中時刻から逆算する弾と敵、縦横描画、3層背景、通常敵3種、自機、中盤／終盤の簡易ボス、音楽イベント同期の側方弾幕、爆発、音声デバイス時計による再生・一時停止・停止・シーク。標準図形素材だけで動作し、素材はDLL相対で読み込む。

専用画面はファイル参照、方向、感度、波形とイベント表示、再生・一時停止・停止・シーク、適用して閉じるを備える。音楽の全体解析はGUI側では別スレッドで実行する。AviUtl2への出力側では新しい音楽を描画前に一度だけ解決し、解析待ち画面が書き出しへ混入しないようにする。以後は上限付きのメモリキャッシュ（最大4構成／PCM合計512MiB）から描画する。

指定曲は`C:\Users\vramw\Music\magnific_aQo5nq8fSh.mp3`。非GUI検証では30.024秒、感度50で39件のイベントを取得し、任意時刻の再描画、命中位置、音声時計と停止・シーク、資源解放を確認した。GUI起動承認が未了のため、画面の実操作・実AviUtl2認識・実聴評価を完了したとは扱わない。

## 描画と性能

標準素材の透明色はマゼンタ、描画原点は中央。D2Dへは透過色をアルファ0へ変換して一度アップロードする。縦横向きとCPU出力の行方向を揃える。D2DのDC描画経路を既定にし、利用不可・描画失敗時はGDIへ戻す。背景・素材・拡縮済みスプライト・出力バッファを再利用する。

同階層SYNC_BreathのD3D11経路も参考にした。人工約1260発、1920×1080の比較でD2DがGDIより有効だったため採用した。D2D内部のハードウェア選択を確認したものではなく、独自D3D11レンダラーを実装したわけではない。測定値と実ホストへの転送を含まない限界はBUILD_RESULTS.mdを参照。

## 主なソース

- `SYNC_RhythmShooter.dpr`：必須3exportと依存ユニット。
- `Source/Plugin/Filter/SYNC_RhythmShooter_FilterPlugin.pas`：ホスト設定、登録、映像出力、メモリキャッシュ。
- `Source/Plugin/Filter/SYNC_RhythmShooter_SettingsForm.pas/.dfm`：専用再生プレビュー。
- `Source/Audio/RhythmAudio.pas`：全曲デコードと立ち上がり検出。
- `Source/Audio/RhythmPlayback.pas`：waveOutの再生位置を唯一のプレビュー時計として使用。
- `Source/Engine/RhythmScene.pas`：時刻から直接決まる配置・弾道・背景・演出。
- `Source/Engine/RhythmD2D.pas`：D2Dへの素材登録と一括描画。
- `Source/Engine/RhythmAssets.pas`：独自図形素材の生成レシピ。
- `Source/Common/RhythmPaths.pas`：DLL相対素材とユーザー別キャッシュ・設定の位置。
- `Source/Lib`：同梱SDK型、フィルターテーブル、MimiCopyStudio由来の子プロセス処理。

ベースの`SYNC_RhythmShooter_LastFrameCapture.pas`も保存しているが、現状の生成映像は元画像の変形を行わない。SDKの型定義はコピー元から変更していない。最新SDKとの比較依頼は移行承認ではない。

## ファイル配置と起動手順

Delphi 37.0／Win64。DPROJからDebug／Releaseをビルドする。ビルドは各`Win64/Debug`／`Win64/Release`にDLLとAUF2を出力し、同じフォルダの`Assets`と`ThirdParty/FFmpeg`へ必要物をコピーする。現在は冒頭の設定どおり、IDEのビルド後イベントで実Pluginフォルダーにも配置する。

`Tools/RhythmPreview.dpr`は同じ専用フォームを使う単独確認用EXE。生成した`RhythmPreview.exe`をDLLと同じ配布構造へ置き、起動後に「参照」で指定曲を開き、解析完了後に「再生」を押す。波形クリックまたはシークバーで移動できる。プラグインでは設定ボタンから同じ画面を開き、「適用して閉じる」で選択オブジェクトの音楽・方向・感度へSDKを通して書き戻す。

実配備先は`C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter`。Release AUF2とRhythmPreview.exe、Assets、ThirdPartyを配置済み。配備先AUF2の非GUI読込・描画と全28ファイルのハッシュを確認した。AviUtl2と専用GUIの起動は未実施。映像フィルターなのでホストの音付き書出しには別途同じ開始位置の音楽オブジェクトが必要である。

キャッシュは`%LOCALAPPDATA%/SYNC_RhythmShooter/Cache`、プレビューの前回設定は同階層の`Preview.ini`。画像やFFmpegはDLL相対、ユーザーデータはユーザー別に分離する。ホストのプロジェクトには標準のfile/select/track項目として音楽・方向・感度を保存する。原曲とPCMキャッシュは配布物に含めない。

## 引継ぎと制約

参考元プロジェクトは変更していない。Git情報・履歴・旧ビルド出力・サンプルAUP2・旧名仕様書・IDEローカル設定は持ち込まない。新GUIDを割り当て、共通SDKとPluginFilterTableはバイト単位で維持した。

任意時刻の決定性と命中同期、標準素材のみでの動作を第1優先とする。短曲のボス調整、より自然な回避・演出、帯域拡張、画像置換、詳細UIは継続課題。GUIの保存再開と実ホスト出力を含め、未確認事項を完成扱いにしない。

既存アプリの強制終了、他プラグインの上書き、音楽の外部送信、commit／pushは行わない。通常ビルド時の本プラグインの配置は冒頭の設定に従う。ソースはCRLF、Pascalの日本語はUTF-8 BOM、共通SDKは元のバイト列を保持する。


## 2026-10-29 敵造形・縦方向の下方進入（無配備候補）

最新 HEAD baedad6 を基準に、通常敵3種・中ボス・大ボスの標準造形と、縦方向だけの下方進入通過編隊を更新。最終 Debug/Release と非GUI回帰は成功。実環境へは配備していない。比較画像、生成物、確認範囲は [ENEMY_DESIGN_20261029.md](ENEMY_DESIGN_20261029.md) を参照。


## 2026-10-29 標準敵機の明度修正（ソースのみ・未ビルド）

敵機が暗いとの実表示フィードバックに対し、標準敵3種とボスの装甲中間色を画像読込時だけ補正。カスタム画像・造形・経路は保持。ユーザーがビルドを行うため、以後こちらからビルド・実行・配備はしない。今回の修正は静的確認のみで、コンパイル・実表示は未検証。詳細は [ENEMY_BRIGHTNESS_20261029.md](ENEMY_BRIGHTNESS_20261029.md) を参照。


## 2026-10-29 小型通常敵の色面修正（ソースのみ・未ビルド）

添付画像を親側で確認し、対象は大量の小型通常敵と確定。標準通常敵3種だけを機種別の有彩色による影・装甲面・明部へ整理。前回残していた最暗部にも対応。ボスの前回補正、カスタム画像、経路、サイズと透明度は維持。今回もビルド・実行・配備なし。詳細と未検証範囲は [ENEMY_SMALL_ENEMIES_20261029.md](ENEMY_SMALL_ENEMIES_20261029.md) を参照。


## 2026-10-30 アニメーション拡張に向けた責務分割（未ビルド）

基準 HEAD は 3cab353。音楽解析、素材バンク、GDI/D2D描画面、背景、絶対時刻のアニメーション実行部を共有側へ分離。敵・弾・ボス・回避・クリアと受入済みの機体配色は専用シーン/素材定義へ移動し、RhythmSceneは既存APIの互換窓口とした。公開設定・JSON・SDK・カスタム素材/AI導線は維持。新しいファイル構成・差替え手順・所有権・静的確認は [ARCHITECTURE.md](ARCHITECTURE.md) を参照。

ビルドはユーザーが行う。今回こちらではビルド・試験実行・アプリ起動・配備・commit/pushは行っていない。新規試験源 AnimationArchitectureSmoke と未実行の TestArchitecture.cmd を追加。以前のビルド成功を今回の成功確認に流用しない。


## 2026-10-30 ボール別プロジェクトとスタイル切替（未ビルド）

基準HEAD 23314ff。RootにSYNC_RhythmBall.dpr/.dprojを追加（暫定表示名リズムボール、グループSYNC）。両プロジェクトは同じソースと設定画面を使い、スタイルはシューティング/ボール。初期値だけをプロジェクト別に設定する。旧JSONのstyle省略はシューティングへ解決。共通はSource/Shared、専用はSource/ShootingとSource/Ball、互換アダプターはSource/Compositionへ整理した。

音楽解析とスタイルの計画準備を分け、作業スレッドで準備し、要求番号とソース条件を照合して採用。ボールは検出時刻の接触・反射・波紋を絶対時刻で描き、準備済み計画JSONを使う。設定、DCU/生成物、配備先は別プロジェクトと分離し、共通音声キャッシュだけを従来の場所で再利用する。標準素材とカスタム画像、シューティングの受入済み演出は維持。

確認はソース・依存・参照・XML・スクリプト構文の静的確認まで。ビルド、試験実行、アプリ起動、配備、commit/pushはしていない。以前の成功結果を今回の成功と扱わない。ユーザー側の確認手順と保存先はBALL_STYLE.mdを参照。

再接続後、切断直前の素材プレビュー調整の保存を読み戻し確認した。最終静的確認は37ユニットの依存・参照・XML・スクリプト構文、候補76ファイルの内容一致、シューティング専用7ユニットと保護対象19ファイルのバイト一致まで。ビルド・試験実行・アプリ起動・配備は未実施で、今回のコンパイル・実表示・音同期は未検証。次のユーザービルド対象は `SYNC_RhythmBall.dproj` と、共通コードを参照する既存 `SYNC_RhythmShooter.dproj`。詳細は [BALL_STYLE.md](BALL_STYLE.md) の再接続後の記録を参照。

## 2026-10-30 ボールをピンボール風へ（未ビルド）

壁の往復から、事前配置/途中出現/流入するバンパーと装甲コアへの接触・反射・破壊を主役に変更。球と障害物を同じ盤面座標で扱い、接触法線・反射方向・Bezier軌道・出現/移動/破壊時刻を計画JSONへ保存する。ボール計画版は2。旧計画は設定画面で音声キャッシュを使って再準備し、適用する。音楽や既存カスタム画像は保持し、シューティングの演出/解析/計画版は変更しない。詳細・再ビルド後の確認手順は [BALL_STYLE.md](BALL_STYLE.md)。

今回もビルド・試験実行・アプリ起動・配備・commit/pushは行っていない。静的確認と試験ソース更新のみで、コンパイル・実表示・実曲同期は未検証。Aup2/sample.aup2を含むユーザー作業は保護する。

## 2026-10-30 ピンボール高感度/適用保存の修正（未ビルド）

配置の進路先読み・戻り探索と、密集音の短い共鳴統合を追加。元の音時刻/強度を計画v3に保持し、計画保存後の再読込検証を通ってから再生/適用する。計画準備と通常設定の保存を分離し、未準備でも設定のみ保存できる。失敗理由・経過時間・準備ログを追加し、例外後の再試行を可能にした。旧計画/欠損/条件不一致/内容検証失敗の案内を分ける。音声キャッシュ・ユーザーJSON/画像・Shootingの演出は保持。詳細と実機未確認の範囲はBALL_STYLE.md末尾。

今回もビルド、試験実行、アプリ起動、配備、commit/pushはしない。次のユーザービルド対象はSYNC_RhythmShooter.dprojおよびSYNC_RhythmBall.dproj。高感度での完走・再生・適用保存は次ビルド後の確認が必要。

## 2026-10-30 リズム花火の追加（未ビルド・未配備）

ボール修正8ファイルの保存照合と静的確認記録を先に完了。その後、SYNC_RhythmFireworks.dpr/.dproj、花火初期スタイル、共通設定画面の3スタイル、専用Plan/Sceneを追加した。音時刻を開花として打ち上げを逆算し、牡丹/柳/二重輪、星空と下部の街並み/地形を標準図形で描く。曲末の余韻用にプレビュー出力だけへ無音を加え、元の音楽/PCM/キャッシュは変えない。既存Shooting/Ballの演出とボールv3修正は維持する。

出力/DCU/設定/配備先は製品別。新規ライブラリやAI素材生成はない。ビルド・試験実行・アプリ起動・音声再生・配備・commit/pushは行わない。次はユーザー側でSYNC_RhythmFireworks.dproj（共有参照のあるSYNC_RhythmShooter/Ballも対象）をビルドし、花火の音同期、背景、余韻、保存再開と旧スタイルを確認する。手順・保存先・未検証はFIREWORKS_STYLE.mdを参照。
## 2026-10-30 明示許可による無配備ビルド確認

RhythmPlaybackのフィールド/メソッド宣言順E2169と、初回ビルドで見つけたW1036/H2164/H2443を修正した。最終ソースでShooter/Ball/FireworksのWin64 Debug/Release、計6構成が成功し、エラー・警告・ヒントは各0。生成物のx64形式と必要export、ソース一致、実Plugin側30ファイルの不変を確認した。詳細・生成物・ログは [BUILD_VERIFICATION_20261030.md](BUILD_VERIFICATION_20261030.md)。

今回はビルドが許可された範囲であり、配備イベントは無効。試験プログラム実行・GUI起動・実配備・commit/pushは行っていない。以前の「未ビルド」は各作業時点の記録。実動作・高感度完走・適用保存・花火の同期は次の確認事項として残る。

### 参考にしたビルド・コメント方針

SYNC_Motion/note.mdを読み、Delphi 37.0のrsvars.bat→MSBuild、Win64 Debug/Release、警告/エラー確認を参照した。名称・出力/配備はこのプロジェクトの設定を使う。

コメントは目的・責務・重要な副作用・値の意味を補い、現状と食い違えば更新する。ユニット先頭と公開APIで担当範囲を示し、処理の言い換えや重複は増やさない。クラス宣言ではフィールドをメソッドより前に配置する。日本語を含むPascal/DPRはUTF-8 BOM、改行はCRLF。SDKの配置・型・アラインメントを意図せず変えない。参照元は変更していない。