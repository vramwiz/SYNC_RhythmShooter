# ホスト設定と描画オフセット

2026-11-04 / 共通12スタイル。

AviUtl2のスクロール方向（小分類）・解析感度を全ホスト版の登録から除き、設定画面の既存JSON direction/sensitivityへ一本化。代わりに「オフセット」を−1.00〜＋1.00秒・0.01秒刻み・初期0秒で追加した。負値は先行、正値は遅延。全種類/EQ/カメラ/透明合成の前に描画時刻を一度だけ変換し、解析・元音時刻・音声再生・計画キーは変えない。

| 設定 | 設定場所・保存 |
|---|---|
| 大・中・小分類 | 設定画面。保存は既存style/directionだけ |
| 解析感度 | 設定画面、JSON sensitivity |
| オフセット | AviUtl2 track、±1秒、step 0.01、初期0 |
| offsetSeconds | 開いた時点のPreview用JSONコピー。ホストではtrackが正 |

## 時刻の契約

`描画時刻 = オブジェクト秒 − オフセット秒`。例えば元音10.00秒の命中は−0.25秒なら9.75秒、＋0.25秒なら10.25秒に見える。音楽ファイル・音声再生時計はそのまま。スライダーstepはSDKの0.01だが、ホストがフレームごとに渡す補間値を不必要に丸めない。範囲外は±1へ制限、非有限のtrack値は0秒へ安全化する。

`RhythmTiming`は純粋な絶対時刻変換だけ。`RhythmScene.Render`の共通入口で一度適用し、個別Scene・EQ・カメラへ同じ時刻を渡す。時刻を積算しないので乱順seekでも同じフレームになる。描画時刻が0未満なら全種類で完全透明、0で通常描画を開始。曲末後は各種類の従来の終端演出を続け、強制ループ/末尾クランプは追加しない。

## ホスト項目と移行

既存の有効な設定JSON・style ID・direction 0/1・sensitivity・計画版/schema1を保持する。offsetSecondsのない旧JSONは0秒。旧ホストの方向/感度だけを持ちJSONがない物件は、項目を削除したため自動回収できない。方向0・感度50を初期値として、設定画面で再入力・準備・適用する。JSON破損/型不正は既存の安全処理と同じく未準備に戻して透明出力する。旧項目名をオフセットへ流用せず、感度値を秒へ取り違えない。

旧方向select/感度trackは非表示に残すのでなく、変数・登録・fallback読込を撤去した。拡大/X/Y/音楽/設定の既存名・型と最初の5項目を維持し、新しいtrack名はオフセット。現代ホストでは設定JSONの既存位置5を維持してその後へoffsetを追加し、無条件hideruleはJSONだけ。非対応ホストはoffsetを通常表示し、JSONだけを閉じた内部グループへ置く。旧ホストの内部JSON位置はグループ移動で変わるが名前と型は保つ。実AUP2の読み込みはGUI禁止のため未実施。

SDKは既存TFILTER_ITEM_TRACKのdouble値/S/E/Stepを用いる。SDKソースは変更していない。ローカルのfilter2.hの「呼出時に現在値へ更新」「step 0.01」契約と既存SDK wrapperを参照。

設定JSONには既存direction/sensitivityを継続保存する。offsetSecondsはPlanのrecipe/variantに入れず再解析を起動しない。旧ビルドは未知JSON値を無視するので、その場合オフセットは反映しない。新TryJSONは追加値がある場合に数値型を検証する。初回回帰でGetValue<Double>が型不正を既定0に落とす点を検出し、数値型チェックを追加した。

## Previewと利用

本人側でDLL反映後、AviUtl2の「オフセット」で調整する。既に有効なPlanがあればオフセット変更だけの再準備は不要。小分類/感度は設定画面で変更し、必要な準備→適用→AUP2保存。ホストの現在オフセットは設定を開く時にPreviewへ渡し、JSONのoffsetSecondsはStandalone Preview用のコピーとして保存する。DLL描画は毎フレームのホストtrackを正としJSONの値で上書きしない。

Previewの音声とwaveform/seek目盛は元音時刻を示し、絵だけ共通Rendererで補正する。未準備時は従来の案内/透明出力のまま。再生中のホストtrack変更やキーフレーム全体はStandalone Previewで再現しない。固定値の比較は全12種類でホストと一致した。

## 検証と範囲

最終30ビルド（12DLL Debug/Release24＋Game/Shooter/Race Preview両構成6）成功。各構成でHostTimingSmoke 14,130照合（201段階・12種/両direction旧JSON・plan保持）、分類2,638照合/360遷移、全12実DLL 192 warm/cold/seek・396ホスト音源/EQ/境界フレーム・288オフセット比較が成功。GDI/Direct2Dとホスト/Previewの時刻一致を検証。MV 18,663,060画素等の照合/24画像、記号342/14画像、音解析11入力385照合も成功。38PNGが両構成一致、0秒の全12種15PNGは開始時と完全一致。

設定フォームは両構成コンパイルのみ、RTTIはフォーム生成なし。新時刻の負/正/0、±1/±0.01、開始直前/0/曲末後、範囲外・非有限値、旧JSON、型不正、0秒への復帰、逆順描画を確認した。

既存114ソース中110本とAUP2/Assets/SDK/ThirdPartyは開始時ハッシュと同一。変更はホスト・設定JSON・Preview受渡し・共通描画入口の4本、新規はRhythmTimingのみ。全115ユニット、最大1442行、循環・フィールド順違反・1500行超は0。音源解析/個別Plan/物理/描画は変更なし。

証跡 `Verification/HostOffset-20261104/{handoff.json,scope-checks.json,source-final.json,Final/}`、試験 `Tests/HostTimingSmoke.dpr` と `Tests/StyleIntegrationSmoke.dpr`。

Computer Use/GUI操作・配備・commit/pushは行っていない。実AviUtl2で既存AUP2を開く移行/パラメータ表示/実音は未確認。SDKの項目名/型を維持しネイティブ保存復元を検証したが、実ホストのAUP2再保存は本人確認が必要。Previewのオフセットは設定画面を開いた時点の固定値で、再生中にホストの時変trackを取得し直さない。オブジェクト範囲外には描画できず、遅延した末尾が切れる場合はオブジェクト長を延ばす。
