# Breakout ビルドエラー修正（2026-10-30、V:側）

対象は `V:/DelphiProg/SYNC_RhythmShooter`。本人の「note.mdを読んでビルド方法を調査してビルドして」という依頼に基づき、今回は実ビルドを実施した。配備・アプリ起動・音声再生・commit/pushは行っていない。

## 原因と最小修正

初回の実コンパイルで `RhythmBreakoutScore.pas(380)` の E2555「シンボル Compare は取得できません」、続いてF2063を再現した。匿名関数から外側のローカル関数Compareを参照していたため、Delphi 37.0でコンパイルできなかった。

比較本体を匿名関数内へ移し、Cost昇順→同値ならSerial昇順という順序を維持した。同じユニットの未使用ローカル変数5個も除いた。製品コードの変更はこの1ファイルだけ。10列下降、逆方向生成、音同期、疎区間の補助反射優先/捕球次点、JSON版2/旧版1互換は変更していない。

## 手順と実行環境

note.mdの通常手順はDelphi 37.0のrsvars.bat→MSBuild、Win64 Debug/Release。通常のBuild.ps1/DPROJには配備イベントがあるため、以前の無配備ビルド記録に従いイベントをグローバルプロパティで空にし、専用出力を使った。

再現コマンドは `Verification/BuildFix-20261030/build-one.cmd SYNC_RhythmBreakout Debug`。全10構成の再実行は同フォルダの `build-all.ps1`。各コマンドは次を指定する。

- `C:/Program Files (x86)/Embarcadero/Studio/37.0/bin/rsvars.bat` を読み、MSBuild `/t:Build /p:Platform=Win64 /p:DCC_BuildAllUnits=true` を実行。ログ中のコンパイラ `-B` を確認した。
- ConfigはDebugまたはRelease。DCC_ExeOutput、DCC_DcuOutput、FinalOutputDir、IntermediateOutputPathは検証用フォルダへ指定。
- RhythmDeployDirectory、PreBuildEvent、PreLinkEvent、PostBuildEventは空。SkipResGeneration=trueとして既存Shooter.resを保持する。

最初の制限環境ではBorland.Globalization.ResourceStringManager.GetUILocaleOverrideStringのレジストリ読取がSecurityExceptionとなり、MSB4061/MSB4060でコンパイル前に停止した。権限付きの同一コマンド実行が承認され、その後は正常にコンパイルできた。別のコンパイラ経路やレジストリ設定変更による回避はしていない。残る権限ブロッカーはない。

## 最終ビルド結果

| 製品 | Win64 Debug | Win64 Release | 各構成のエラー / W警告 / Hヒント |
|---|---|---|---|
| SYNC_RhythmBreakout | 成功 | 成功 | 0 / 0 / 9 |
| SYNC_RhythmShooter | 成功 | 成功 | 0 / 0 / 9 |
| SYNC_RhythmBall | 成功 | 成功 | 0 / 0 / 9 |
| SYNC_RhythmFireworks | 成功 | 成功 | 0 / 0 / 9 |
| SYNC_RhythmRunner | 成功 | 成功 | 0 / 0 / 9 |

全10構成が終了コード0。残る9件はすべてH2077「代入された値が使われていない」で、PreparedDataに4、BreakoutScoreに3、BreakoutPlanに1、RunnerPlanに1。MSBuildではヒントもwarningとして表示されるため、MSBuildの警告診断数は各9件。WコードのDelphi警告は0。無関係な共通処理の修正や診断抑制は行っていない。

## 成果物と証跡

出力は `Win64/BuildFix-20261030/<製品名>/<Debug|Release>/`。各フォルダのbuild.log、DLL、DLLと同バイトのAUF2を保持した。AUF2へのコピーは検証用出力内のみで、配備先へコピーしていない。これはビルド成果物で、Assets/FFmpeg付き配布パッケージではない。

- Breakout: [Release AUF2](Win64/BuildFix-20261030/SYNC_RhythmBreakout/Release/SYNC_RhythmBreakout.auf2)、[Releaseログ](Win64/BuildFix-20261030/SYNC_RhythmBreakout/Release/build.log)、[Debugログ](Win64/BuildFix-20261030/SYNC_RhythmBreakout/Debug/build.log)。
- 全10構成の終了コード、E/W/H件数、DLL/AUF2のSHA256、ログSHA256、コンパイル入力SHA256、必須exportは `Verification/BuildFix-20261030/build-results.json`。
- 初回コンパイルエラーは同フォルダの `Breakout.Debug.initial.log`。修正直後の成功ログも別名で保持した。
- `verify-build.js`で全DLLがPE32+/AMD64、InitializePlugin/UninitializePlugin/GetFilterPluginTableを持つこと、DLL/AUF2同一性、配備イベント実行なしをバイト解析で確認。DLLをロード/実行してはいない。
- 既存配備先 `C:/ProgramData/aviutl2/Plugin/SYNC_RhythmShooter` の28ファイルがビルド前と同一。既存ソース/設定UI/DPI/他スタイル/プロジェクト/素材/ユーザーAUP2も、今回のScore修正と記録以外は作業前のハッシュを保持する。

独立した反射譜モデル25ケースと静的ソース確認も修正後に再確認。旧静的検証の出力ハッシュには、今回の作業開始前に更新済みだったDCU11件との不一致があるため、出力を戻さずソース対象で再確認した（--source-only、275保護ファイル一致）。今回の入力保持は新しい開始時baselineでも確認した。詳細はpreexisting-output-differences.json。これはDelphi試験実行やGUIの代替ではない。

**未実施:** ネイティブ試験実行、プレビュー/AviUtl2起動、音声再生、実表示と負荷確認、配備、commit/push。新しい反射譜へ反映するにはビルド成果物の反映後に設定画面で再準備・適用・作品保存が必要。旧計画は互換再生を維持する。
