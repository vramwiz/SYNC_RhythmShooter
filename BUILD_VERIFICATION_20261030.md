最新の保存再開修正は [BALL_PERSISTENCE.md](BALL_PERSISTENCE.md)（Ball新規v5、旧v4互換、未ビルド・未実行）。この6構成の成功は今回変更前の履歴。

**この文書は直線軌道/花火拡張より前の6構成ビルドの履歴。現在の変更後ソースに対する成功ではない。最新は [TRAJECTORY_UPDATE_20261030.md](TRAJECTORY_UPDATE_20261030.md)（ソース修正と静的確認のみ、未ビルド・未実行・無配備）。**

# 2026-10-30 無配備ビルド確認

対象: `D:/DelphiProg/MyApp/SYNC_RhythmShooter`、HEAD `23314ff` と現在の未コミット変更。今回の明示許可に基づきビルドした。試験プログラム実行・GUI起動・実配備・commit/pushは行っていない。

## 修正

- `RhythmPlayback.pas` のGetDuration宣言の後にフィールドが続いていたためE2169になっていた。全フィールドをメソッド宣言より前へ移動した。
- 初回Debugビルドで見つけたW1036は、画像回転のアルファ有無を固定し、ポインター初期化と走査行取得の経路を明示して修正した。警告抑制はしていない。
- BallPlanの未使用変数T（H2164）を削除し、設定画面へSystem.UITypesを明示してMessageDlgのインラインヒント（H2443）を解消した。
- Playbackのユニット目的・公開APIの責務/副作用コメントを補った。動作機能の追加はしていない。

## 最終結果

Delphi 37.0 / Win64。最終ソースに対して各構成を `DCC_BuildAllUnits=true`（-B）で実行した。

| 製品 | Debug | Release | エラー | 警告・ヒント |
|---|---|---|---|---|
| SYNC_RhythmShooter | 成功 | 成功 | 各0 | 各0 |
| SYNC_RhythmBall | 成功 | 成功 | 各0 | 各0 |
| SYNC_RhythmFireworks | 成功 | 成功 | 各0 | 各0 |

6件すべてのDLLがPE32+ / AMD64で、InitializePlugin、UninitializePlugin、GetFilterPluginTableの必要exportを持つことをファイル解析で確認した。DLLのロード実行による確認ではない。

## 生成物とログ

検証ルート:

`C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030`

各生成物は `Outputs/<製品名>/<Debug|Release>/<製品名>.dll` と同名 `.auf2`。AUF2はこの検証出力内だけで同バイトコピーし、SHA256一致を確認した。DebugのRSMも残している。各フォルダのbuild.logが最終ビルドログ。

| 製品 | Debug AUF2 | Release AUF2 |
|---|---|---|
| Shooter | [Debug](C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030/Outputs/SYNC_RhythmShooter/Debug/SYNC_RhythmShooter.auf2) | [Release](C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030/Outputs/SYNC_RhythmShooter/Release/SYNC_RhythmShooter.auf2) |
| Ball | [Debug](C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030/Outputs/SYNC_RhythmBall/Debug/SYNC_RhythmBall.auf2) | [Release](C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030/Outputs/SYNC_RhythmBall/Release/SYNC_RhythmBall.auf2) |
| Fireworks | [Debug](C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030/Outputs/SYNC_RhythmFireworks/Debug/SYNC_RhythmFireworks.auf2) | [Release](C:/Users/vramw/Documents/Codex/2026-10-28/task-3/build-check-20261030/Outputs/SYNC_RhythmFireworks/Release/SYNC_RhythmFireworks.auf2) |

同ルートのresults.jsonに全パス、SHA256、exportを記録。初回の3件の診断を含むログはAttempts/Shooter.Debug.initial.logへ分けた。生成物はビルド確認用で、標準素材・FFmpeg等をまとめた配布一式は作成していない。

## 無配備と保全

- DCC_ExeOutput、DCC_DcuOutput、Obj/中間出力を検証ルートへ指定した。
- RhythmDeployDirectory、PreBuildEvent、PostBuildEvent、PreLinkEventをMSBuildグローバルプロパティで空にした。最終6ログにBuildPlugin/配備イベントの実行はない。
- 最終6構成はSkipResGeneration=trueとし、既存Shooter.resを使用した。初回の資源再生成後も元の資源とSHA256が同じことを確認している。
- ビルド中の48ソース入力の一致、実Plugin側30ファイルの内容とファイル集合の一致、参照したSYNC_Motion/note.mdの不変を確認した。
- 再接続後にも6ログ、DLL/AUF2、SHA256とソース一致を再確認した。コンパイラ処理は残っていない。

## 参考手順とコメント

`D:/DelphiProg/MyApp/SYNC_Motion/note.md` を読み、Delphi 37.0のrsvars.batからMSBuildを呼ぶ手順、Win64 Debug/Release、エラー/警告の確認、UTF-8 BOMとCRLF、目的・責務・重要な副作用を説明するコメント方針を参照した。参照元は変更していない。現プロジェクトの名称・出力方針を維持し、検証用DLL/AUF2を保存した。

再現用の検証限定コマンドは、検証ルートのbuild-one.cmd。製品名とDebug/Releaseだけを受け取り、全ビルドイベントを無効化する。通常のDPROJ/Build.ps1は引き続き従来の配備設定を持つため、この検証と区別する。

## 未検証

コンパイルと静的な生成物確認まで。Ball高感度の計画生成・再生・適用保存、花火の実表示・音同期・余韻、GUI操作、AviUtl2へのロード、性能、試験プログラムの実行は未確認。ビルド成功を実動作成功として扱わない。
