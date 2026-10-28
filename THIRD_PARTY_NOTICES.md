# 参照・同梱物

## FFmpeg

MimiCopyStudioの既存`ThirdParty\FFmpeg`から、FFmpeg 8.1.1-full_build-www.gyan.devのCLIと依存DLLをローカルコピーした。元フォルダは変更していない。CLIは別プロセスとしてWAV／MP3をPCM16ステレオ44100Hzへ変換する。通信プロトコルはfile/pipeに限定する。ネットワーク接続、音楽の外部送信、追加ダウンロードは行わない。

同梱ビルドはGPL v3。ライセンス全文・ビルド構成・元由来情報は`ThirdParty/FFmpeg/LICENSE`、`README.txt`、`provenance.json`に保存した。配布時はこれらの文書を含むフォルダ一式を保持する。

元配布物に記載された参照先：FFmpeg https://ffmpeg.org/ 、Windows build https://www.gyan.dev/ffmpeg/builds/ 、対応ソース https://github.com/FFmpeg/FFmpeg/commit/239f2c733d 。

## MimiCopyStudioの参考コード

音楽全体のデコード・キャッシュ、音声デバイス時計による同期、停止時の資源管理を参考にした。`Source/Lib/Process/MimiChildProcess.pas`は元の`Source/Core/MimiChildProcess.pas`を変更せずコピーし、引用符処理、ローカル子プロセス管理、取消・タイムアウト処理を再利用した。他のMimiCopyStudioソースや設定、既存バイナリは変更していない。

## プラグイン雛形と標準素材

`SYNC_Base_画像参照するフィルター`の必要ソースとフォーム・リソースをコピーした。AviUtl2FilterTypes.pasとPluginFilterTable.pasはバイト単位で変更していない。SDKの更新・移行は実施していない。

Assetsの標準BMPは本プロジェクトの`Source/Engine/RhythmAssets.pas`に記述した独自の図形から生成する。既存ゲームの素材やAI生成画像は利用していない。`Tools/BuildAssets.dpr`で再生成できる。

検証曲はユーザー指定のローカルファイルであり、Assetsや配布物には同梱しない。現在のPCMキャッシュはLocalAppDataのSYNC_RhythmShooter配下、検証画像・JSONはWin64出力内に保存する。初期検証時にWin64出力内へ作成したPCMもローカル検証用として保持し、配布・公開しない。

## Revision 4 の既存AI連携再利用

RIGMMaker/Source/Integrations/RigmCodexClient.pasをRhythmCodexClientへ適応した。元SHA256は815CCD17227ADB51707961640031BD123A3A55B6683AA6F5140E4C25425BAAA0。専用app-serverの匿名パイプと画像通知処理を再利用し、名称・画像用文言・取消・早着通知処理を整合した。AIArtToPSDの画像受渡し・原本保護・要求指紋・採用の分離も参照。両参照元のファイルは変更していない。Verification/codex-reuse-origin.jsonを参照。画像の復号・拡縮はWindows標準WIC、PNG書込はDelphi VCLを利用し、新規の外部有料APIやキー保存機能を追加していない。
