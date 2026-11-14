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
| `20_slime_source.png` | 滞留と流出を確認するU字の透過素材 |
| `21_slime_arriving.png`～`23_slime_dripping.png` | 到達・滞留・凹部からの滴下 |
| `24_slime_person.png` | 人物・段差・斜面に沿うスライムと下余白 |
| `slime_demo.gif` | `animation` 指定で生成する32フレームのスライム見本 |
| `slime_person_demo.gif` | 人物・輪・段差・斜面で軌道を確認する32フレームの見本 |
| `slime_motion.csv` | 人物画像での接触前後の位置・速度・状態の診断ログ |
| `startup_rain_000.png` など | 雨・雪・スライムの開始状態0／50／100を表示開始時刻で比較 |
| `startup_state.png` | `make_contact_sheet.ps1 -StartupOnly` で作る3×3の比較画像 |
| `compose_snow_normal.png` など | 連続噴射を含む素材・発生・動きの組み合わせ例 |
| `combinations.png` | `make_contact_sheet.ps1 -CompositionOnly` で作る3×3の組み合わせ一覧 |
| `visibility_snow_before.png` / `visibility_snow_after.png` など | 雪・砂・花びら・落ち葉・紙吹雪・ひょう・光・インクのFull HDでの変更前後 |
| `visibility.png` | `make_contact_sheet.ps1 -VisibilityOnly` で作る8素材の変更前後一覧 |
| `water_spray_fullhd.png` / `water_spray_contact.png` | 連続噴射の水流と、人物のアルファ輪郭へ当たったしぶき |
| `snow_fullhd.png` | 大きくした雪のFull HD透過フレーム |
| `slime_shading.png` | 同じ透明度の明部と暗部を検証するスライム |
| `water_impact_fullhd.png` | 手動ノズルから人物の肩へ当たる水のFull HD透過フレーム |
| `water_impact_demo.gif` | Full HD描画を縮小し、放出・到達・飛散を示す32フレームの見本 |
| `contact_sheet.png` | PowerShellで作る暗い市松模様上の一覧 |
| `motion_demo.gif` | 雨・積雪量の変化・水の連続噴射・噴水を並べた32フレームの動画見本 |
| `checks.txt` | 検証結果とFull HDの参考測定 |

PNGには元の透明度を保存し、一覧とGIFには見やすい背景を合成します。
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
- 全12スタイルの既定値が、透明キャンバス上へ自然に表示されること。
- 素材10種類・発生5種類・動き5種類の全250組み合わせが、SDKなしで実際の不透明画素を描くこと。
- 発生リストの表示順と数値IDを区別し、連続噴出と爆発が入れ替わらないこと。
- 水が発生方法に応じて雨・水の発射・噴水になり、他の素材も動きを変えて素材が変わらないこと。
- 重力0・広がり360で単発／連続の全方向移動を設定できること。
- 通常への再設定で風・渦が残らず、組み合わせ後も逆シーク・寿命・開始状態を維持すること。
- 横風・強風の雪が上部だけに偏らず、画面下部まで流入すること。
- Full HDで8素材のアルファ96以上の粒子面積が旧基準の2倍を超え、雨・スライムの基準値は変わらないこと。
- 連続噴射が対象へ届いて飛散し、出続けること。指定位置・反転・開始・継続時間・周期・接触のみの描画・逆シークも確認する。
- 雪のアルファ160以上の面積が従来の組み合わせ設定の2倍以上になり、スライムの明暗が同じ透明度で区別できて逆シークでも再現すること。
- Full HDで水が人物のアルファ輪郭へ届く前と後を分け、衝突後に水しぶきが跳ね返ること。GIFでも人物の色が保たれること。
- 接触・蓄積だけを描くモードで空中粒子が残らないこと。
- Full HDの初期フレーム下部にも雪があり、連続フレームでキャッシュが働くこと。
- GIFの全フレームで色と形状が崩れていないこと。
- 粘度で近傍粒子の速度差が減り、まとまりで粒子間の隙間がつながること。
- 斜面を伝い、蓄積を有効にしたU字のくぼみでも前面へ滴下して流出すること。
- 粘性粒子の逆シーク・端数時刻・キャッシュなしで画素が一致すること。
- 下余白で元画素と床位置を保ち、最大2,048粒と速度上限を守ること。
- 人物画像で輪郭追従中の粒子が画像内部へ横送りされないこと。
- 左右両方の面で、離れる粒子を引き戻さず、近づく粒子に外向き法線を返すこと。
- 開始状態0で全12スタイルの粒子・接触・蓄積がなく、50が途中の状態になること。
- 雪の蓄積が空から育ち、開始状態の変更・逆シーク・端数フレーム・時間補正を再現できること。
- 開始状態100で従来の出力を維持し、発射・噴出の発生時刻を進めないこと。

失敗時は終了コード1を返します。Debugでは範囲・整数オーバーフロー検証を有効にし、Releaseでも同じ検証を実行できます。
この成功は、AviUtl2の実画面上での操作確認とは区別してください。
