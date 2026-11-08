# 純Delphi MP3デコーダーへの切り替え（2026-11-08）

MP3の準備時デコードを `V:\DelphiProg\MP3_Decoder` の `pascal-minimp3-2` に切り替えた。プレビューは従来のWindows waveOutでPCMを再生する。MP3のデコード・再生でFFmpeg、Media Foundation、外部デコーダーEXEは呼び出さない。WAVは既存のFFmpeg変換を使用する。

## 変更とキャッシュ

- `Source/Lib/MP3Decoder` にAPIと演算部の7ユニットを取り込み、7製品と共通のプレビュー／試験ビルドの検索パスへ追加した。参照元は変更せず、取り込み時は改行だけCRLFに統一した。Pascalトークンの一致と元／取込後のSHA-256を記録した。
- `RhythmAudioDecode` はMP3をプロセス内で44.1kHz・16bit・ステレオのPCMへ変換する。キャンセル・例外時の一時PCMとWAV用ログも後始末する。
- MP3のPCM・イベントJSON・索引JSONにデコーダー版を含めた。旧FFmpeg由来キャッシュとユーザーの準備済み計画は削除・上書きしない。更新後、MP3の音声キャッシュが必要なプレビューでは設定画面で再準備する。
- WAVのキャッシュ名と処理は従来どおり。CC0の出典・修正記録を `ThirdParty/MP3Decoder` に置き、配布ZIPへの同梱とカタログのアンインストール対象を更新した。公開済みの版番号・AUF2ハッシュは変更していない。

## 検証

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

開始時の409ファイルを、既存の未コミット変更と未追跡ファイルも含めて次へ退避した。

`Win64/Backups/NativeMP3-20261108-130920`

復元前の確認：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win64\Backups\NativeMP3-20261108-130920\Restore.ps1 -CheckOnly
```

元のソースへ戻す：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win64\Backups\NativeMP3-20261108-130920\Restore.ps1
```

今回の変更ファイルだけを退避時のバイト列へ復元し、今回追加したソース・文書は削除する。開始時点のスライダー修正などは残る。作業後に編集された対象ファイルがある場合は、全ファイルの事前確認で停止する。Gitの履歴・インデックスは変更しない。

復元対象はソースとビルド設定。試験バイナリと試験キャッシュは保持するため、ローカル試用版も旧方式へ戻す場合は、復元後に `Scripts/Build.ps1 -Config Release -Tools -NoDeploy` で再ビルドする。既存の実配備先と通常の `Win64/Debug`／`Win64/Release` は今回更新していない。

## 対応範囲

元デコーダーの制約も引き継ぐ。free-formatと途中でサンプルレート／チャンネル数が変わるMP3は拒否する。CRC値の検証、VBRI等の特殊なギャップレス情報には未対応。44.1kHz以外のリサンプルは独自フィルターのためFFmpegとビット一致は保証しない。全曲をPCMへ展開し、出力上限は512 MiB。今回の検証はすべてのMP3や破損入力への適合保証ではない。
