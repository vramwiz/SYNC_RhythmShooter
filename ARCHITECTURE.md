新規追加は [RUNNER_STYLE.md](RUNNER_STYLE.md)。現在HEAD基準6df4731、4製品/4スタイル。Source/Runnerに計画/描画、Shared/Settings/RhythmPreparedDataに準備済みJSON/メタデータ保存・復元を追加。既存Ball5/旧4・Fireworks2・Shooting1と公開SDKを維持。今回ソースと静的確認のみ。

最新: [BALL_PERSISTENCE.md](BALL_PERSISTENCE.md)。Ballの新規計画版5、旧v4互換。計画本文に描画復元メタデータ、オブジェクト参照にsourceStampを保存。ホストは軽量な復元データ→既存計画検証を使い、PCMを必須にしない。Shooting=1、Fireworks=2を維持。今回未ビルド・未実行。

最新差分: [TRAJECTORY_UPDATE_20261030.md](TRAJECTORY_UPDATE_20261030.md)。計画版はShooting=1、Ball=4、Fireworks=2。共通の計画参照にvariantを追加し、花火の華やかさだけへ使用する。Shooting/Ballは0で従来のキー式を維持。プロジェクト分離・SDK境界・保存先は変更しない。今回変更後は未ビルド・未実行。

最新の追加: [FIREWORKS_STYLE.md](FIREWORKS_STYLE.md)。Shooting/Ball/Fireworksの3製品・3スタイルを共有基盤で扱う。今回もビルド/実行は未確認。

# 共通コードとアニメーション構成（2026-10-30、未ビルド）

現在の基準は `23314ff`。同じRootに `SYNC_RhythmShooter` と `SYNC_RhythmBall` のDPR/DPROJを置き、ソース本体はコピーせず共有する。プロジェクトごとの識別名・初期スタイルはDPRの `ConfigureRhythmProduct` で設定する。Rootフォルダは現状のままで、ソース参照は相対パス。

## フォルダの責務

| フォルダ | 内容 |
|---|---|
| Source/Shared/Audio | 純粋なPCM/RMS/アクセント解析と音声時計 |
| Source/Shared/Render | アニメーション実行部、素材バンク、GDI/D2D描画面、背景、図形プリミティブ |
| Source/Shared/Settings | スタイル列挙、プロジェクト識別、既存JSON、計画参照 |
| Source/Shared/Common・Assets | DLL相対/ユーザー保存先、画像検証・読込・保存 |
| Source/Shared/UI・Integrations・Host | 共通設定画面、波形、カスタムデザインと既存AI連携、AviUtl2の公開境界 |
| Source/Composition | スタイルとシーンの組立、準備ワーカー、従来の音声/素材カタログの互換アダプター |
| Source/Shooting | 自機・敵・ボス・弾幕・回避・クリア、標準素材生成と受入済み配色 |
| Source/Ball | 接触時刻の計画/保存検証、ボール描画 |
| Source/Lib | 既存SDK・共通外部コード。今回変更していない |

Sharedの設定画面からCompositionへ処理を委譲し、スタイル固有計画は各専用ユニットへ置く。Host/Formユニットには互換性のため既存のSYNC_RhythmShooter名を残しているが、両DPRから同じソースを参照する。別のShooter DLLを読み込む依存ではない。

## 差替え口

`TAnimationScene.Prepare/Draw` は絶対時刻、方向、描画範囲を受ける。`TAnimationRenderer.Create(Scene, ImageBank)` がシーンと素材バンクを所有し、拡大/X/Y、描画失敗時のGDI再描画、共通の案内表示を担う。入力音声は借用であり、呼出側がPrepare/Draw中の生存を保証する。

`RhythmScene` は既存TRhythmRenderer APIを保つ構成窓口。スタイル切替は新しいシーンと素材バンクを作成してから交換する。シューティング用の公開ヘルパーも維持する。新しい種類は専用Scene/計画/必要な素材バンクを追加し、スタイル定義と構成箇所だけを拡張する。共有描画基盤へ敵/弾の条件分岐を増やさない。

画像は素材バンクを通して変更し、派生・透過・縮小・GPUキャッシュをまとめて更新する。カスタム画像への色補正は行わない。図形はSurface.Circle/Line、画像はSurface.DrawAssetで両描画経路を使う。Canvasへ直接GDI描画をするシーンはUseD2DをFalseにする。既存Parallaxを使う場合は背景6スロットを方向×3層で用意する。

## 音声と計画

RhythmAudioAnalysisは44.1kHzステレオS16 PCMから時刻・強度・波形だけを求める。Composition/RhythmAudioは旧イベントJSONのlane/flightやボス参照を残す互換境界。BallはHitsの時刻・強度と有効音声終端を使い、敵レーン・弾速・ボス計画は使わない。

RhythmPrepareが専用画面の準備スレッドを担当する。音楽/感度は音声キャッシュの責務、スタイル/方向は演出計画の責務とする。ボールは接触配列を別の計画JSONへ保存し、設定JSONには版・条件・キー・内容SHAを記録する。本番は準備済みデータを読み、解析/ボール計画生成を開始しない。

UI要求は番号で照合し、古い完了結果を採用しない。再準備中は再生を止め、以前の結果を新設定へ適用しない。正常・失敗時に操作を復帰し、画面終了では自分のワーカーを中止・回収する。

## 互換性と確認状態

既存schema 1、素材ID、ホスト公開項目、SDK型、AI作成/採用経路を維持。styleがない旧JSONはシューティングとする。新規設定のみプロジェクト別の初期スタイルを使う。Shooting専用7ユニットは処理を変更せず移動した。標準画像・カスタム画像・ユーザーデータは今回書き換えていない。

ユーザー向けの仕様、保存先、ビルド、確認手順は [BALL_STYLE.md](BALL_STYLE.md) を参照。旧テストとScriptsの探索パス、両DPR/DPROJ、両プレビューDPRを新配置に合わせる。将来Rootを改名しても相対参照は維持される。ProductIdを変更する場合は別途保存先の移行が必要。

今回の確認は静的な依存、参照、XML、スクリプト構文、移動前との内容照合まで。**ビルド・試験実行・アプリ起動・配備・commit/pushは行っていない。コンパイルと実表示は未検証。**

## ピンボール計画v2

Source/Ball/RhythmBallGeometry は盤面の等方座標、障害物/曲線の型、接触半径、Bezier凸包と移動円の交差検査を担当。RhythmBallPlan は音時刻から障害物の出現・流入・反射・破壊と軌道を計画しJSON保存。RhythmBallScene は同じ座標変換で盤面とエフェクトを描く。準備スレッド/本番描画の責務境界は維持する。スタイルID ball は固定、StylePlanVersion(rsBall)のみ2へ上げ、Shootingは1のまま。ビルド/実行未確認。

## 花火の追加（2026-10-30）

- Source/Fireworks/RhythmFireworksPlan: 音の時刻から打ち上げ・開花・種類/色/粒子数/余韻を計画しJSON保存。
- Source/Fireworks/RhythmFireworksScene: 星空・街並み/地形、打ち上げ、牡丹/柳/二重輪、終端静止を共通D2D/GDI描画面で描く。
- Shared/Settingsはstyle=fireworksと新製品IDを追加。既存の列挙値・JSON ID・SDK公開設定は維持。Composition/RhythmSceneが3種類を組み立て、RhythmPrepareが準備と保存後の読込検証を担当する。
- Shared/Audio/RhythmPlaybackは任意のプレビュー余韻を私有出力バッファへ無音追加する。解析済み音声は借用のまま変更しない。既存呼出しの既定値は追加0秒。花火のみ、作業スレッドから返された描画終端までの余白を渡す。再生・停止・シークは同じ音声デバイス時計を使い、別の壁時計を混ぜない。
- 新プロジェクトSYNC_RhythmFireworksは出力/DCU/設定/配備先/GUIDを分離する。各製品から3スタイルを選べる。ホスト描画は準備済み計画を読み、音声解析を始めない。

共有UI/工場/ビルド探索パスだけを拡張し、Shooting専用ユニットとBall v3の生成/描画は変更しない。新規アニメーションは、Style ID/版、専用Plan/Scene、準備・組立・UI選択、プロジェクト参照と出力、試験ソースの順に追加する。共通音声解析/再生・描画面は複製しない。