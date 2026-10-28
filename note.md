# SYNC_RhythmShooter 作業ノート

**最新は[REVISION4.md](REVISION4.md)／[カスタムデザインの使い方](CUSTOM_DESIGN.md)。** 設定画面タイトルは Revision 4。15素材の個別設定と専用Codex連携を実装し、実AI生成・実GUI操作は未確認。以下の基本版記録は履歴として保持する。


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

Delphi 37.0／Win64。DPROJからDebug／Releaseをビルドする。ビルドは各`Win64/Debug`／`Win64/Release`にDLLとAUF2を出力し、同じフォルダの`Assets`と`ThirdParty/FFmpeg`へ必要物をコピーする。実Pluginフォルダへの自動配備イベントはない。

`Tools/RhythmPreview.dpr`は同じ専用フォームを使う単独確認用EXE。生成した`RhythmPreview.exe`をDLLと同じ配布構造へ置き、起動後に「参照」で指定曲を開き、解析完了後に「再生」を押す。波形クリックまたはシークバーで移動できる。プラグインでは設定ボタンから同じ画面を開き、「適用して閉じる」で選択オブジェクトの音楽・方向・感度へSDKを通して書き戻す。

実配備先は`C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter`。Release AUF2とRhythmPreview.exe、Assets、ThirdPartyを配置済み。配備先AUF2の非GUI読込・描画と全28ファイルのハッシュを確認した。AviUtl2と専用GUIの起動は未実施。映像フィルターなのでホストの音付き書出しには別途同じ開始位置の音楽オブジェクトが必要である。

キャッシュは`%LOCALAPPDATA%/SYNC_RhythmShooter/Cache`、プレビューの前回設定は同階層の`Preview.ini`。画像やFFmpegはDLL相対、ユーザーデータはユーザー別に分離する。ホストのプロジェクトには標準のfile/select/track項目として音楽・方向・感度を保存する。原曲とPCMキャッシュは配布物に含めない。

## 引継ぎと制約

参考元プロジェクトは変更していない。Git情報・履歴・旧ビルド出力・サンプルAUP2・旧名仕様書・IDEローカル設定は持ち込まない。新GUIDを割り当て、共通SDKとPluginFilterTableはバイト単位で維持した。

任意時刻の決定性と命中同期、標準素材のみでの動作を第1優先とする。短曲のボス調整、より自然な回避・演出、帯域拡張、画像置換、詳細UIは継続課題。GUIの保存再開と実ホスト出力を含め、未確認事項を完成扱いにしない。

既存アプリの強制終了、他プラグインの上書き、音楽の外部送信、commit／pushは行わない。ソースはCRLF、Pascalの日本語はUTF-8 BOM、共通SDKは元のバイト列を保持する。
