## 2026-11-11 ソース配置の整理

改修済みデコーダーは共通音声ソースとして Source/Shared/Audio/MP3Decoder に移動した。出典・CC0ライセンス・修正記録と比較用原典も同じフォルダーに置く。ThirdPartyからのビルド/配布時コピーを撤去した。以下は導入時点の記録。

# 純Delphi MP3デコーダーへの切り替え（2026-11-08）

MP3の準備時デコードを `V:\DelphiProg\MP3_Decoder` の `pascal-minimp3-2` に切り替えた。プレビューは従来のWindows waveOutでPCMを再生する。MP3のデコード・再生でFFmpeg、Media Foundation、外部デコーダーEXEは呼び出さない。WAVはWindows標準のMedia Foundationで復号し、MP3と共通のリサンプラーで44.1kHzへ変換する。64bit floatのmono/stereo WAVはDelphiで読み込む。FFmpeg本体・DLL・子プロセス処理・ダウンロードスクリプトは削除済み。

## 変更とキャッシュ

- `Source/Lib/MP3Decoder` にAPIと演算部の7ユニットを取り込み、7製品と共通のプレビュー／試験ビルドの検索パスへ追加した。参照元は変更せず、取り込み時は改行だけCRLFに統一した。Pascalトークンの一致と元／取込後のSHA-256を記録した。
- `RhythmAudioDecode` はMP3をプロセス内で44.1kHz・16bit・ステレオのPCMへ変換する。キャンセル・例外時の一時PCMも後始末する。
- MP3のPCM・イベントJSON・索引JSONにデコーダー版を含めた。旧FFmpeg由来キャッシュとユーザーの準備済み計画は削除・上書きしない。更新後、MP3の音声キャッシュが必要なプレビューでは設定画面で再準備する。
- WAVのPCM・解析索引も `windows-wave-1` で分離し、旧キャッシュを保持する。CC0の出典・修正記録を `ThirdParty/MP3Decoder` に置き、配布ZIPへの同梱とカタログのアンインストール対象を更新した。カタログにv1.0.1を追加し、同梱物の更新時は専用の `ThirdParty` を入れ替える。v1.0.0の履歴は保持する。

## 2026-11-08 FFmpeg同梱の削除

本人がMP3の正常なデコードを確認した後、FFmpeg本体と依存DLL、ダウンロードスクリプト、子プロセス起動ユニット、全製品・プレビュー・試験の参照を削除した。削除物と既存成果物は復元用の退避だけに保持している。

WAVはMedia Foundationで元のレートのPCM16へ復号し、MP3と共通のリサンプラーで44.1kHzステレオへ変換する。Windows側で直接リサンプルした際の末尾数サンプルの丸めを回避する。Media Foundationが受理しない64bit floatのmono/stereo WAVはDelphiで読み込む。WAVのPCM・イベント・索引は `windows-wave-1` に分離し、旧キャッシュを維持する。

- `NativeWaveSmoke` はDebug/Releaseとも23条件・793,991照合に成功。PCM8/16/24/32bit、float32/64bit、8～96kHz、mono/stereo、6ch、WAVEFORMATEXTENSIBLE、奇数長の追加チャンクを含む。長さ、音の開始と末尾、キャッシュ復元、キャンセル、不正入力、GUIのSTAスレッドも確認した。
- MP3はDebug/Releaseとも従来の28正常入力・410照合と実曲の再生・シークを通過。WAVの既存 `AudioEdges` も成功した。
- 7製品のDebug/Release DLLとReleaseプレビューの計21構成に加え、ShooterのDebugプレビューもビルドした。ShooterのDLLホストで保存復元・シーク・ホスト音源・オフセットを確認した。
- `Setup/SYNC_RhythmShooter.zip` は23ファイル・2,455,165 byte。旧ZIPの99,221,424 byteから縮小し、外部デコーダーを含まないことを確認した。
- カタログはv1.0.1（2026-11-08）を追加。AUF2のXXH3-128は `edd5362c171c02f3838c83fecded423a`。v1.0.0の履歴は保持した。カタログのインストール／更新とアンインストールを隔離フォルダーで再現し、旧ランタイムの削除とDesignAssets・ユーザー設定の保持を確認した。

今回の証跡は `Win64/NoFFmpegVerification`。通常の `Win64/Debug` と `Win64/Release` も更新した。実AviUtl2への配備、GitHubへの公開、commit/pushは行っていない。

## 初回MP3差し替え時の検証

- Delphi 37.0／Win64で7製品のDebug／Release DLL（14構成）とReleaseプレビュー（7構成）がビルド成功。取り込み元の未使用値に関するH2077が2件あり、既存コードのヒントも残る。
- FFmpegを置いていない試験フォルダーで `NativeMP3Smoke` がDebug／Releaseとも410照合を通過。9サンプルレート、mono／stereo、VBR、極短音声、日本語パスを含む28正常入力について、既存の参照WAVとのサンプル数、PCM／メタデータの復元と再利用を確認した。44.1kHz入力の比較差は最大1 LSB。
- 有効な旧形式キャッシュの流用防止と保持、フレーム途中／PCM公開直前のキャンセル、一時ファイルの後始末、不正MP3の7条件を確認した。
- 実曲4曲を既存のFFmpeg由来PCMと時間シフトなしで比較。サンプル数は全件一致し、最大差1～2 LSB、RMS差0.059～0.068 LSB、SNR約99.4～100.6 dB。比較元キャッシュのSHA-256も維持した。今回の比較でFFmpegは起動していない。
- 約175.035秒と約29.637秒の実曲で、waveOutの再生時計、一時停止、シーク、再開、停止を確認した。聴感による全曲通し確認は未実施。
- 既存の `AudioEdges`（WAV、感度、無音、同一パスの内容変更、PCMなし復元、不正入力）と `AnimationArchitectureSmoke` も成功。
- FFmpegを置かない7製品のDLLで、13バリエーションのホスト統合試験も成功。GDI／Direct2Dの保存復元・逆順シーク208照合、ホスト音源429照合、オフセット312照合を通過した。

検証記録は `Win64/NativeMP3Verification`。再実行例：

```powershell
.\Scripts\TestNativeMP3.ps1 -Fixtures V:\DelphiProg\MP3_Decoder\tests\runs\20261107-082142-103 -Config Debug -Music '任意の音楽.mp3' -Audio
```

`-Audio` を付けると短い音声出力試験を行う。試験はLOCALAPPDATAを試験用ディレクトリへ切り替え、本人のキャッシュを更新しない。Fixturesは参照WAVを含むデコーダー側の基本試験データを指定する。

## 試用と復元

試用プレビューは `Win64/Local/SYNC_RhythmShooter/Release/RhythmPreview.exe`。同じ出力先へAUF2・Assets・第三者同梱物もそろえた。実AviUtl2への配備、GUI起動、作品の書き換え、commit／pushは行っていない。

FFmpeg削除前の429ソース・文書と、削除したランタイム、既存のビルド成果物・ZIPを次へ退避した。

`Win64/Backups/RemoveFFmpeg-20261108-133207`

復元前の確認：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win64\Backups\RemoveFFmpeg-20261108-133207\Restore.ps1 -CheckOnly
```

元のソースへ戻す：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win64\Backups\RemoveFFmpeg-20261108-133207\Restore.ps1
```

今回の変更ファイルだけを退避時のバイト列へ復元し、今回追加したWAVユニットと試験を削除する。確認済みの純Delphi MP3デコーダーとスライダー修正は残る。作業後に編集された対象ファイルがある場合は、全ファイルの事前確認で停止する。Gitの履歴・インデックスは変更しない。

復元対象はソースとビルド設定、退避した同梱物、更新した製品バイナリと配布ZIP。試験キャッシュは保持する。実AviUtl2への配備は行っていない。初回のMP3差し替え前の退避は `Win64/Backups/NativeMP3-20261108-130920` に別途保持している。

WAVの対応コーデックは [Windows Media Foundationの対応形式](https://learn.microsoft.com/en-us/windows/win32/medfound/supported-media-formats-in-media-foundation) に従う。追加のシステムDLLは同梱しない。

## 対応範囲

元デコーダーの制約も引き継ぐ。free-formatと途中でサンプルレート／チャンネル数が変わるMP3は拒否する。CRC値の検証、VBRI等の特殊なギャップレス情報には未対応。44.1kHz以外のリサンプルは独自フィルターのためFFmpegとビット一致は保証しない。全曲をPCMへ展開し、出力上限は512 MiB。今回の検証はすべてのMP3や破損入力への適合保証ではない。
