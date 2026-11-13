# 通常のEXEによるパーティクル描画実験

`ParticleFX_Experiment.dproj` はコンソールプログラムです。
ホスト非依存の設定・粒子計算・接触判定・Direct2D描画器を直接使用します。
AviUtl2のSDK・プラグインコード・プラグインDLLを読み込まず、ホストのウィンドウも操作しません。

## ビルドと実行

プロジェクトのルートで実行します。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild Experiments\ParticleFX_Experiment.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
.\Win64\Experiment\ParticleFX_Experiment.exe
.\Experiments\make_contact_sheet.ps1
```

GIFも作る場合は、出力フォルダーと `animation` を指定します。

```powershell
.\Win64\Experiment\ParticleFX_Experiment.exe 'D:\DelphiProg\MyApp\SYNC_ParticleFX\Win64\Experiment\Preview' animation
```

ビルドと実行の対象はこの実験用EXEだけです。プラグインを作成・配置する処理はありません。

## 生成する素材と画像

出力先は通常 `Win64\Experiment\Preview` です。

| ファイル | 内容 |
| --- | --- |
| `00_source.png` | 頭・肩・段差・穴・斜面・アルファ64/192の半透明面を持つ透過素材 |
| `01_rain.png` | 元画像への雨・接触飛散 |
| `02_snow_000.png`～`04_snow_100.png` | 積雪量0・50・100の比較 |
| `05_sideways_rain.png` | 横方向の雨と側面衝突 |
| `06_upward_snow.png` | 上向きの粒子・重力と下面への蓄積 |
| `07_water_shot.png` / `08_fountain.png` | 指定位置からの発射と噴出 |
| `09_petals.png`～`16_vortex_fan.png` | 花びら・紙吹雪・爆発・砂・ひょう・インク・吹雪・扇状の渦 |
| `17_water_default.png` / `18_fountain_default.png` | 発生位置を自動にしたスタイル既定値 |
| `19_contact_accumulation_only.png` | 空中粒子を省いた付着・積雪 |
| `contact_sheet.png` | PowerShellで作る暗い市松模様上の一覧 |
| `motion_demo.gif` | 雨・積雪量の変化・水の発射・噴水を並べた32フレームの動画見本 |
| `checks.txt` | 検証結果とFull HDの参考測定 |

PNGには元の透明度を保存し、一覧とGIFには見やすい市松模様を合成します。
素材はプログラムが生成するため、外部画像や追加の画像処理ライブラリは必要ありません。

## 検証する内容

- PNGの上下・RGB・アルファが元のバッファと一致すること。
- アルファ64と192をしきい値128で区別し、全方向で外向き法線を取得すること。
- 高速粒子が1pxの壁をすり抜けず、1px幅の輪郭にも積雪が見えること。
- 重力に面する蓄積と、風上側の薄い付着を分けること。
- 蓄積量0で古い雪が残らず、50・100で面積が増えること。
- 自動流入、発射と独立した重力、無重力、速度上限、間欠噴出が動くこと。
- 突風・乱流・渦を含め、逆シークと新しいキャッシュで画素が一致すること。
- 半透明素材との合成で色を暗くせず、元画像を変更しないこと。
- COM終了とスレッド交代を挟んでも描画器を再利用できること。
- 全11スタイルの既定値が、透明キャンバス上へ自然に表示されること。
- ホスト非依存の20プリセットで、有限・上限内の粒子が生成されること。
- 接触・蓄積だけを描くモードで空中粒子が残らないこと。
- Full HDの初期フレーム下部にも雪があり、連続フレームでキャッシュが働くこと。
- GIFの全フレームで色と形状が崩れていないこと。

失敗時は終了コード1を返します。Debugでは範囲・整数オーバーフロー検証を有効にし、Releaseでも同じ検証を実行できます。
この成功は、AviUtl2の実画面上での操作確認とは区別してください。
