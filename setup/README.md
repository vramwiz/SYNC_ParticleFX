# パーティクル演出（SYNC_ParticleFX）

雨・雪・水しぶきなどを描き、画像のアルファ輪郭へ衝突・付着・蓄積させるAviUtl2用フィルタープラグインです。Windows 64bit / AviUtl2 2.1.16以降を対象とします。

## インストール・更新

1. AviUtl2を終了します。
2. `SYNC_ParticleFX.zip` を展開し、中の `SYNC_ParticleFX` フォルダーをAviUtl2の `Plugin` フォルダーへコピーします。標準の配置先は `C:\ProgramData\aviutl2\Plugin\SYNC_ParticleFX` です。
3. AviUtl2を起動し、画像オブジェクトに「SYNC」グループの「パーティクル演出」を追加します。

更新も同じ場所へ上書きします。ZIPにはAUF2本体・このREADME・ライセンス類を収録します。アンインストール時は、AviUtl2を終了して同梱の5ファイルを削除してください。

## 使い方

1. 「スタイル」で雨、雪、水をかける、花びら、落ち葉、紙吹雪、砂、ひょう、噴水、光の粒・爆発、インクから素材を選びます。
2. 一番上の「プリセット」で候補を選び、すぐ下の「プリセット適用」を押します。選択だけでは演出は変わりません。
3. 適用によって変化した発生量・速度・方向・重力・風などを個別に調整します。再び適用すると関連項目を置き換えます。「標準」で現在のスタイルの基準へ戻せます。

プリセットは現在のスタイルに対して設定します。「雪＋暴風雨・吹雪」「水をかける＋バケツ」「噴水＋間欠噴出」などを組み合わせてください。位置・開始時刻・シード・色・接触・蓄積・描画範囲はプリセット適用時にも維持します。

発生角度0は、雨・雪などが下、水をかける・インクが右、噴水が上です。重力方向0は下、風向0は右です。重力強度0で無重力になります。連続型の「発生位置を自動」を有効にすると進行方向の反対側から流入します。発生位置X/Yは画像中央を原点とします。

「画像と接触する」を有効にすると、入力画像のアルファを判定します。蓄積量は0～100で、0なら蓄積を描きません。「接触・蓄積のみ」の描画モードで、全画面の粒子と人物などへの付着を重ねられます。

描画は入力画像の範囲に収まり、範囲外はクリップされます。接触対象はこのフィルターに渡される画像だけです。雨・水・光には厚い蓄積を作りません。液体は粒子と飛散による視覚表現です。

## ライセンス・ソース

Copyright (c) 2026 VRAMの魔術師

本体のソースコードはGNU General Public License v3.0（GPL-3.0-only）です。全文は同梱の `LICENSE`、移植元と著作権表示は `THIRD_PARTY_NOTICES.md` を参照してください。

AviUtl ExEdit2 Plugin SDK由来の定義はMITライセンスです。Copyright (c) 2025 Kenkun。全文を `ThirdParty/LICENSE.AviUtl2-SDK.txt` に同梱しています。

ソース公開先: [vramwiz/SYNC_ParticleFX](https://github.com/vramwiz/SYNC_ParticleFX)

## 配布ZIPの作成・カタログ登録（開発用）

1. Delphi / Win64のReleaseをビルドします。既定の入力は `C:\ProgramData\aviutl2\Plugin\SYNC_ParticleFX\SYNC_ParticleFX.auf2` です。
2. [xxHash公式配布](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)の `xxhsum.exe` を `Win64\Dependencies\xxHash-0.8.4` またはPATHが通った場所に置きます。
3. `setup\SYNC_ParticleFX.catalog.json` の `version` 末尾に公開タグと日付を設定します。初期値は `v1.0.0` です。次の版は末尾に追加します。
4. `setup\make_release_zip.bat` を実行します。`setup\SYNC_ParticleFX.zip` を作成し、ZIPに収録したAUF2と同じバイト列のXXH3-128を末尾バージョンへ記録します。
5. 同じソースをGitHubのタグへ保存し、ReleaseにZIPを添付します。カタログ登録には `SYNC_ParticleFX.catalog.json` を使用します。初期JSONの空のハッシュは、バッチ実行後の実際の値で置き換わります。

別の出力フォルダーやxxhsumを使用する場合:

```powershell
.\setup\make_release_zip.bat -ReleaseDirectory "D:\Release" -XxhsumPath "D:\Tools\xxhsum.exe"
```

バッチは既存AUF2の梱包とローカルJSONのハッシュ更新を行います。プラグインのビルドとGitHubへの公開は別途行ってください。公開先の初期設定は `vramwiz/SYNC_ParticleFX` です。

ZIP内の構成:

```text
SYNC_ParticleFX/
  SYNC_ParticleFX.auf2
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  ThirdParty/
    LICENSE.AviUtl2-SDK.txt
```
