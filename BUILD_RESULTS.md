# 最終ビルド・検証記録

**最新は[REVISION31.md](REVISION31.md)（設定画面タイトル Revision 3.1）。** 星の速度・サイズ・光跡、明示クリアと終端後の離脱を追加。旧本体の完全非表示は確認待ち。


**最新の限定更新は[REVISION3.md](REVISION3.md)を参照。** 設定の簡素化・フレーム中の解析停止・不規則な3層星・登場離脱を追加。完全な内部項目非表示は対応本体の確認待ち。波形のちらつき修正はユーザー受入済み。


2026-10-28。最終の標準弾速・距離による逆算、横向き素材、行方向、設定画面終了処理を含むソースで再ビルド・回帰検証した。旧生成物の成功を最終版の結果へ流用していない。機能別の実装状態は[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)。

## 保存先・ビルド

| 対象 | 場所／結果 |
|---|---|
| プロジェクト | `D:\DelphiProg\MyApp\SYNC_RhythmShooter\SYNC_RhythmShooter.dpr`、同名DPROJ |
| 環境 | Delphi 37.0、Win64 |
| 最終Debug | 2026-10-28 04:00:10 UTC、警告0・エラー0 |
| 最終Release | 2026-10-28 04:00:33 UTC、警告0・エラー0 |
| Debug生成物 | `Win64\Debug\SYNC_RhythmShooter.dll`、`.auf2`、`.rsm` |
| Release生成物 | `Win64\Release\SYNC_RhythmShooter.dll`、`.auf2` |
| 専用プレビュー | 各構成の`RhythmPreview.exe`（同一フォームを使う単独確認用） |
| ログ | `Win64\Debug.build.log`、`Win64\Release.build.log` |
| ビルド再実行 | `Scripts\Build.ps1 -Config Debug -Tools`、`-Config Release -Tools` |

Debug AUF2のSHA256は`93BFE252285CC6FAAB41C714711BB667AF5EDC2B5F24ADFBBD0FE34C53C47BB6`。Release AUF2は`39D421E17808715F6DACB24E544D80EEACED8956BA5D24A13F6BDCD5CAE2F425`。DLL→AUF2はコピーであり、内容は同一。

## export・登録・最初のフレーム・再初期化

`Win64\Debug\Verification\plugin-smoke.json`、`Win64\Release\Verification\plugin-smoke.json`。

- 両DLLの`InitializePlugin`、`UninitializePlugin`、`GetFilterPluginTable`をGetProcAddressして実呼出し。
- 初期化は成功値1、登録グループは`SYNC`、表示名は`リズムシューティング`、説明は`リズムシューティングフィルタープラグイン`。
- 設定項目は音楽ファイル（file）、スクロール方向（select）、解析感度（track）、設定（button）の4つでnil終端。
- nil映像入力の境界、1280×720のRGBA出力、アルファ255を確認。
- 音楽の初回解決から描画まで約52ms（Debug）／55ms（Release、既存PCMキャッシュ）。最初のフレームと直後の同時刻フレームが一致し、解析待ち画面が混入しない。
- 縦横とも時刻8.69秒→24秒→8.69秒で一致。Debug／ReleaseでもRGBAのSHA256が一致。
- 初期化・終了を2回実行して成功。GUI設定ボタンは実行していない。
- CPU描画・BGRA→RGBA変換・検証側のメモリコピーを含む1920×1080コールバック平均はDebug約16.3ms／Release約18.6ms。この単回測定を構成間の優劣の根拠にはしない。実AviUtl2のGPUアップロードは含まない。

## 指定MP3・命中・弾速・再描画

`Win64\Debug\Verification\smoke-audio.json`が最終の音声込み回帰結果。`smoke.json`は同じ製品ソースで行った追加の画像保全・描画比較結果。

- 原曲：`C:\Users\vramw\Music\magnific_aQo5nq8fSh.mp3`。変更・外部送信していない。
- 原曲SHA256：`2e722315dc71767cc2cfa7ff5f32ea25f8a1036787476cf221d0a6cf58551fe3`。
- 30.024013605秒、44100HzステレオPCM16、5,296,236バイト。
- 感度50で39イベント。最小間隔180ms、負の発射時刻なし。
- 最初の命中は2.20秒、最終方式での発射は約1.680896秒。
- 命中時刻の弾／敵位置誤差は最大`5.56e-17`、標準弾速1.25に対する最大誤差は`1.09e-12`。
- PCMキャッシュ再利用を確認。最終読込・解析約39ms、再利用再読込約35ms。最初の未キャッシュ時は約379msだった。
- GDIとD2Dの両経路で、縦横とも任意時刻の再描画が一致。
- 生成画像を視認し、上下方向、横向き素材、透過色、通常敵3種、自機、弾、爆発、大量弾が描画されることを確認。これは生成画像の確認でありGUI操作確認ではない。
- 指定曲の実際の中盤／終盤のボスを縦横で生成し、`sample-boss0-direction0.bmp`等4枚へ保存。中盤の縦画像（約14.48秒）と終盤の横画像（約26.68秒）を視認した。

## WAVと入力の境界

`Win64\Debug\Verification\audio-edges.json`。

- 自作WAVの0.4／1.2／2.1／3.4秒の4アクセントを20ms以内で検出。
- 感度1と100で既知パルスを検出。
- 無音で0イベント。同じパスの音声内容を変更すると異なるSHA256・キャッシュを使用。
- 不正MP3、欠損ファイルは例外として報告。ユーザーの曲は変更していない。

## 音声デバイス時計（GUI・実聴とは別）

最終回帰で指定曲の短時間出力を行った。

- 再生位置は0.220635秒→0.472676秒へ進行。
- 一時停止前後は0.490748秒で一致（250ms待機）。
- 一時停止中に4.5秒へシーク、再開後4.724875秒へ進行。
- 再生中17秒へシーク、その後17.185329秒を取得。
- 停止で位置0、waveOutリセット・バッファ解除・デバイス解放完了。
- スピーカー音を聴いて同期を評価したものではない。実画面の映像との同時操作確認も未完了。

## D2D採用の根拠と測定条件

同階層SYNC_BreathのD3D11・CPU readback方式を読んだ後、既存GDIとD2D DC描画を同じ場面で比較した。[MicrosoftのDC相互運用資料](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-gdi-interoperation-overview)に従ったDC描画経路を使用する。

| 条件 | GDI | D2D |
|---|---:|---:|
| 1920×1080、指定曲中の120時刻、平均 | 11.34ms | 13.75ms |
| 1920×1080、人工の約1260発のボス弾＋通常敵・背景・爆発、10時刻平均 | 51.39ms | 16.24ms |

人工場面は30秒へ1501イベントを20ms間隔で置き、14.45秒付近の10時刻（1ms刻み）を描画した。1.8秒分の14発扇状弾が約1260発同時に存在する。これは現行検出器の180ms制限より密な性能負荷用データで、指定曲の実際の弾数ではない。

両経路は同じ素材・位置計算・画面サイズを用い、素材読込とD2Dアップロードは測定前に済ませる。D2DはEndDrawによるDCへの反映を含み、実使用フラグを記録した。人工大量弾で約3.2倍有効だったためD2Dを採用し、GDIフォールバックを残した。通常場面の改善や60fpsを保証する結果ではない。D2D内部のGPU選択や実AviUtl2の転送は未測定。

同じ製品ソースの追加画像保全回では、通常場面GDI10.07ms／D2D12.59ms、人工大量弾GDI38.62ms／D2D17.28msだった。単回測定の変動を含め、大量弾では約2.2～3.2倍、通常場面ではGDIの方が速かったという範囲で判断する。

## 実配備と相対素材

- 配備先：`C:\ProgramData\aviutl2\Plugin\SYNC_RhythmShooter`。
- AUF2、RhythmPreview.exe、AssetsのBMP15枚、FFmpeg依存とLICENSE等、計28ファイルを新規配置。
- 元々同名フォルダがないことを確認し、非空フォルダでは中断するスクリプトを使用。他のプラグインを上書きしていない。
- `deployment-manifest.json`へSHA256・サイズを記録し、全28ファイル一致を確認。
- 配備AUF2のSHA256は上記Releaseと一致。
- 配備先AUF2を非GUIで読み、必須export・登録・最初のフレーム・任意時刻描画・終了再初期化を確認。DLL相対のAssetsを読み、開発Releaseと縦横のRGBAハッシュが一致。
- 根拠：`Win64\Release\Verification\Deployed\plugin-smoke.json`と同フォルダの画像。
- 原曲・PCMキャッシュ・検証用音声は配布フォルダへコピーしていない。
- キャッシュと前回プレビュー設定は`%LOCALAPPDATA%\SYNC_RhythmShooter`配下。画像とFFmpegはDLL相対。

## GUI承認・環境中断・未確認事項

Computer Useの対象は`D:\DelphiProg\MyApp\SYNC_RhythmShooter\Win64\Debug\RhythmPreview.exe`。実画面で指定曲を選び、同期再生・シーク・保存を確認するための起動承認が03:00頃と03:21頃の2回タイムアウトした。承認済みとは扱わず、同じ依頼の反復や別経路起動を行っていない。拒否ではなく未承認・未起動である。

環境が一時利用不可となった後、03:18 UTCに復旧。最初のGet-Locationとファイル・プロセス読取は成功し、重複プロセスがないことを確認して再開した。

実AviUtl2の起動・認識・設定ボタン・保存再開・実書出し、専用GUIの操作とレイアウト、実聴による同期評価は未実施。非GUIの音声時計・画像確認で置き換えたとは扱わない。最終状態でAviUtl2とRhythmPreviewのプロセスは0。

コピー元の必要9ファイルは保存したSHA256と一致。SDK2ユニットとMimiChildProcessは元と同じバイト列を保持する。仕様原文は337行。詳細な最終ファイル照合は`Verification`の要約を参照。

他アプリの強制終了、他プラグイン上書き、SDK更新、原曲変更・外部送信、commit／pushは行っていない。
