# SYNC_ParticleFX 作業ノート

## プロジェクトの前提

- プロジェクトフォルダーは `D:\DelphiProg\MyApp\SYNC_ParticleFX`、Delphi プロジェクト名は `SYNC_ParticleFX`。AviUtl2 のグループ名は `SYNC`、プラグイン名は `パーティクル演出`。
- `D:\DelphiProg\MyApp\SYNC_Mine` のプロジェクトと共通基盤をコピーした。ビルド設定はユーザー指定により `D:\DelphiProg\MyApp\SYNC_PhotoShot\SYNC_PhotoShot.dproj` から引き継ぐ。
- 現在はプラグインとして作らず、通常のEXE `Experiments/ParticleFX_Experiment.dproj` で描画処理を開発・検証する。AviUtl2 SDK・プラグインコード・プラグインDLLを実験用プロジェクトから参照しない。
- ユーザー指定により、生成・配置したプラグインバイナリと、追加した単独版プラグイン用プロジェクト・グループプロジェクトを削除した。元のプロジェクトと実装ソースを保持する。プラグインの再ビルド・配置は行わない。
- 粒子・接触・蓄積・描画は `Source/Common` のホスト非依存コードとする。画素は独自の4バイト `TFXPixelRGBA`（ストレートRGBA）を使う。既存の `git_init.bat` は保持する。
- スタイルとプリセットの初期値生成も共通処理に置く。実験用のビルド・テストをSDK依存へ戻さない。

## ビルド

- Delphi 37.0、Win64。現在ビルドするのは `Experiments/ParticleFX_Experiment.dproj` のみ。警告・エラーともに0を原則とする。
- プロジェクトのルートで次を実行する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild Experiments\ParticleFX_Experiment.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild Experiments\ParticleFX_Experiment.dproj /t:Build /p:Config=Release /p:Platform=Win64'
.\Win64\Experiment\ParticleFX_Experiment.exe
```

## ビルド後イベントとプロジェクト登録

以下は保持している元のプラグインプロジェクトの設定。現在は実行しない。
実験用EXEは `Win64\Experiment` に出力し、ビルド後イベント・ホストEXE設定を持たない。

- Debug / Release / Win64 のビルド設定とビルドイベントは `SYNC_PhotoShot.dproj` からそのままコピーする。コピーした設定内では、出力先フォルダー名の `SYNC_PhotoShot` だけを `SYNC_ParticleFX` に変更する。
- 両構成の `DCC_ExeOutput` は `C:\ProgramData\aviutl2\Plugin\SYNC_ParticleFX\`。このフォルダーへ直接 DLL を出力し、ビルド後イベントで同じ場所の `.auf2` にコピーする。コピー失敗時は終了し、成功後に中間 DLL を削除する。Release では RSM も削除する。コマンドはコピー元の複数行のまま保持する。
- 成果物は両構成とも `C:\ProgramData\aviutl2\Plugin\SYNC_ParticleFX\SYNC_ParticleFX.auf2`。DCU は従来どおり `Win64\Debug\DCU` / `Win64\Release\DCU` に出力する。
- ユニットを追加したら、`.dpr` の `in` 指定と `.dproj` の `DCCReference` を両方更新する。フォームやフレームの IDE メタデータも対応させる。
- ビルド設定・ビルド後イベント・デバッガー設定はコピー元をそのまま維持する。プロジェクト名・GUID・配置先の変更と、最小構成に必要なユニット参照の整理だけを行う。最小構成化を理由に、ビルド設定を削除・再構成しない。
- Debug / Release のデバッガーホストは、コピー元の PhotoShot と同じ `D:\aviutl2_v2.1.16\aviutl2.exe` とする。

## ソース配置

- `SYNC_ParticleFX.dpr` は DLL の初期化・終了とエクスポートを担当する。
- `Source/Plugin/Filter` には、AviUtl2 のコールバックやプラグイン登録など、プラグイン固有の処理を置く。
- `Source/Lib` には、AviUtl2 SDK の型定義やフィルターテーブルの登録処理など、共通基盤を置く。
- `Source/Common/ParticleFX_Types.pas` は設定・スタイル・画素・決定的乱数、`ParticleFX_Simulation.pas` は発生と運動、`ParticleFX_Collision.pas` はアルファ接触と蓄積、`ParticleFX_Renderer.pas` はDirect2D描画と合成を担当する。
- `Experiments` は透過素材生成・画像/GIF出力と検証を担当する。ホストへの登録・接続の検証は含めない。

## コメント・分割・文字コード

以下はコピー元の `note.md` と共通のルールとする。

- ユニット先頭に目的と責務を書く。公開処理には入出力と重要な副作用を記載し、状態の有効範囲、所有権、保存対象を必要に応じて明記する。コードをそのまま言い換えるコメントは避ける。
- 日本語を含む `.pas`、`.dpr`、Windows PowerShell 用の `.ps1` は UTF-8 BOM 付きとし、改行は CRLF とする。
- 1 ユニットは約 1,500 行を目安に責務で分け、関連ユニットは機能別フォルダーに置く。フォームの `.pas` と `.dfm` は同じフォルダーに置く。
- フォームは操作と画面状態を担当する。機能追加時は検証・解析・描画をそれぞれの処理側に置く。
- AviUtl2 SDK 型の順序・サイズ・配置を変える場合は、公式 SDK の定義と照合する。

## 描画処理と検証方針（2026-11-13）

- 粒子の番号・発生時刻・シードから初期値を決め、1/60秒の固定刻みで計算する。整数刻みだけをキャッシュし、逆シークやキャッシュなしでも同じ画素へ再現する。グローバル乱数・前フレームの画像を使わない。
- 11スタイル、連続・発射・爆発／放射・噴出の4方式を共用する。角度0はスタイル基準、重力0度は下、風向0度は右。風・突風・乱流・渦は独立して扱う。
- 接触は入力アルファの区間走査で行い、外向き法線から飛散・反射方向を決める。1pxの障害物も判定し、飛散・反射後の再接触も処理する。
- 蓄積は重力に面する輪郭・量0～100・最大厚・シードから直接生成する。傾斜限界へ近づくと薄くし、風上には薄い付着を別に加える。画像範囲外はクリップする。
- Direct2Dで透明なWIC描画面へ描き、PBGRAをストレートRGBAへsource-over合成する。元画像を別に保ち、描画がない画素のRGBAを変更しない。
- COMのMTAを所有cookieで生存させ、スレッド交代・COM終了を挟んでも資源を再利用できるようにする。外部STAで作った資源は呼出内で解放する。
- 普通のEXEが、頭・肩・段差・穴・斜面・半透明面を持つ画像を生成して描画する。PNGの色・アルファ、全方向の衝突、蓄積量、逆シーク、無重力、間欠噴出、Full HD、GIF全フレームを確認する。
- 詳細と再実行方法は `Experiments/README.md`。現在の検証にプラグインDLLのロードや模擬SDK呼出しを含めない。IDEとAviUtl2は操作・起動しない。
- 液体は粒子と飛散の視覚表現で、連続した流体の体積計算ではない。候補の全素材を実装したものではない。

## 今回の確認結果

- 通常のEXEのみをDebug / Releaseでビルドし、警告0・エラー0。Debugの検証83項目、GIFを含めたReleaseの検証85項目が成功した。
- 20枚の透過PNG、32フレームのGIF、一覧画像を `Win64/Experiment/Preview` に生成した。GIFの中間フレームも別の画像デコーダーで取り出し、色と形状を目視確認した。
- SDK参照・プラグインDLLのロード・模擬SDK呼出しは実験用から除去済み。通常EXEへ分離した時点で、こちらで生成したAUF2と付随デバッグファイルを削除した。その後に利用者がビルドした成果物は削除しない。
- 元の `.dproj` は追加ユニット参照以外、保存したビルド設定と一致している。AviUtl2とIDEを起動・操作していない。
- 検証ログは `Win64/Checks/standalone-debug.log` / `standalone-release.log`、結果一覧はプレビュー内の `checks.txt`。

## プリセットと配布準備（2026-11-13）

- プリセット選択と「プリセット適用」ボタンを標準項目の先頭へ置く。選択だけでは描画を変えず、ボタンが編集APIを通して関連項目へ一括設定する。適用後は各項目の値だけを使用する。
- Aul2AudioFilterの方式を参考にし、公式SDKのcallback2で対象オブジェクトとエフェクト名を受ける。同じフィルターが複数ある場合も、押したエフェクトを対象にする。
- 位置・開始時刻・シード・色・接触・蓄積・描画範囲は適用時に維持する。プリセット変更で前の風・渦・重力などが残らないよう、関連項目は毎回基準から設定する。
- プラグインのビルド・配置は実行せず、アダプターはDCUへの単体コンパイルで確認する。通常EXEによる描画検証は引き続きSDK非依存で行う。元のdprojとビルドイベントは変更しない。
- GitHub向けREADME、GPL本文、由来の表記、SDKのMITライセンスを用意する。コピー元のGPL-3.0を維持する。
- `setup/make_release_zip.bat` とPS1はSYNC_Mine由来。入力は既存の `C:\ProgramData\aviutl2\Plugin\SYNC_ParticleFX\SYNC_ParticleFX.auf2`。ビルドや公開は行わず、ZIPとカタログの末尾バージョンのXXH3-128を更新する。
- カタログの初期版はv1.0.0、ハッシュはバッチ実行前なので空欄。最新のReleaseを利用者がビルドした後、バッチで配布物を作る。ZIPの検証は作業用コピーで行い、本番のJSONやAUF2を変更しない。
- 今回の変更後も通常EXEのDebugは83項目、GIFを含むReleaseは85項目が成功。アダプターのDCU単体コンパイルも警告・エラー0。配布処理は別の作業用コピーで、5ファイルの内容・末尾バージョンだけのハッシュ更新・再実行・入力不足時の既存成果物の保持を確認する。
