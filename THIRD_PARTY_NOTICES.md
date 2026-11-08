# 参照・同梱物

## 純Delphi MP3デコーダー

`V:\DelphiProg\MP3_Decoder` の `pascal-minimp3-2` を `Source/Lib/MP3Decoder` へコピーした。MP3のデコードと44.1kHz・16bit・ステレオへの変換をプロセス内で行い、FFmpegやMedia Foundationは呼び出さない。再生は既存のWindows waveOutを使用する。参照元プロジェクトは変更していない。

Layer IIIの演算部分は [minimp3](https://github.com/lieff/minimp3) の [Delphi移植](https://github.com/gustavoeenriquez/delphi-libraries)（固定commit `849dbaf1892486a6dc5f1ebb555c949a6c4dd4d9`、CC0-1.0）に修正を加えたもの。ライセンス、元ソースとハッシュ、修正内容、今回取り込んだ7ユニットのSHA-256は `ThirdParty/MP3Decoder` に保持する。配布ZIPには `LICENSE.md`、`provenance.json`、`CORE_CHANGES.md`、`integration.json` を含める。

## Windows標準のWAV読み込み

WAVの復号と多チャンネルからのステレオ変換にはWindows標準のMedia Foundationを使用する。44.1kHzへの変換はMP3と共通のリサンプラーで行う。WindowsのシステムDLLは配布物に含めず、デコード時に遅延読み込みする。参照したAPI宣言はWindows SDK 10.0.19041の `mfobjects.h`、`mfreadwrite.h`、`mfapi.h`。FFmpegとその関連DLLは同梱・呼び出ししない。

## MimiCopyStudioの参考コード

音楽全体のデコード・キャッシュ、音声デバイス時計による同期、停止時の資源管理を参考にした。外部デコーダー用の子プロセス実装は削除済み。他のMimiCopyStudioソースや設定、既存バイナリは変更していない。

## プラグイン雛形と標準素材

`SYNC_Base_画像参照するフィルター`の必要ソースとフォーム・リソースをコピーした。AviUtl2FilterTypes.pasとPluginFilterTable.pasはバイト単位で変更していない。SDKの更新・移行は実施していない。

Assetsの標準BMPは本プロジェクトの`Source/Engine/RhythmAssets.pas`に記述した独自の図形から生成する。既存ゲームの素材やAI生成画像は利用していない。`Tools/BuildAssets.dpr`で再生成できる。

検証曲はユーザー指定のローカルファイルであり、Assetsや配布物には同梱しない。現在のPCMキャッシュはLocalAppDataのSYNC_RhythmShooter配下、検証画像・JSONはWin64出力内に保存する。初期検証時にWin64出力内へ作成したPCMもローカル検証用として保持し、配布・公開しない。

## Revision 4 の既存AI連携再利用

RIGMMaker/Source/Integrations/RigmCodexClient.pasをRhythmCodexClientへ適応した。元SHA256は815CCD17227ADB51707961640031BD123A3A55B6683AA6F5140E4C25425BAAA0。専用app-serverの匿名パイプと画像通知処理を再利用し、名称・画像用文言・取消・早着通知処理を整合した。AIArtToPSDの画像受渡し・原本保護・要求指紋・採用の分離も参照。両参照元のファイルは変更していない。Verification/codex-reuse-origin.jsonを参照。画像の復号・拡縮はWindows標準WIC、PNG書込はDelphi VCLを利用し、新規の外部有料APIやキー保存機能を追加していない。
