# リズムシューティング

音楽を解析し、曲に合わせた映像を自動生成するAviUtl2用フィルタプラグインです。設定画面から宇宙シューティング、ピンボール、トロッコアクション、クラッシュキャノン、MV向けの演出などを選べます。

1. AviUtl2で「SYNC」の「リズムシューティング」フィルタを追加します。
2. AviUtl2のフィルタ項目「音楽ファイル」でWAVまたはMP3を指定し、「設定」を開きます。バリエーションを選んで解析・準備し、プレビューで確認して「適用して閉じる」を押します。
3. 音声付きで出力する場合は、同じ音楽をAviUtl2のタイムラインにも配置し、フィルタを適用したオブジェクトと開始位置をそろえます。

手動インストールの場合は、ZIP内の `SYNC_RhythmShooter` フォルダを AviUtl2 の `Plugin` フォルダ（通常は `C:\ProgramData\aviutl2\Plugin`）に配置します。本プラグインのMITライセンス本文は `LICENSE` に収録しています。同梱のFFmpegについては `THIRD_PARTY_NOTICES.md` と `ThirdParty/FFmpeg/LICENSE` を参照してください。

## 配布ZIPを作る

リポジトリの `Setup/make_release_zip.bat` を実行すると、`Win64/Release/SYNC_RhythmShooter.auf2` を使って `Setup/SYNC_RhythmShooter.zip` を作成します。`-ReleaseDirectory` で無配備ビルドの出力先も指定できます。

```powershell
.\Scripts\Build.ps1 -Config Release -NoDeploy
.\Setup\make_release_zip.bat -ReleaseDirectory .\Win64\Local\SYNC_RhythmShooter\Release
```

FFmpegの実行ファイルとDLLは `Scripts/PrepareFFmpeg.ps1` で復元できます。カタログ用のハッシュ計算には [xxHashのWindows版](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4) の `xxhsum.exe` を使います。`Win64/Dependencies/xxHash-0.8.4` に置くか、PATHに追加してください。

公開するタグと公開日を `SYNC_RhythmShooter.catalog.json` の `version` に設定します。次の版は配列の末尾に追加してください。バッチは末尾のエントリに、ZIPへ入れたAUF2の `XXH3_128` を記録します。GitHub Releasesに `SYNC_RhythmShooter.zip` を添付し、AviUtl2 カタログのパッケージ登録でJSONを入力します。
