# 花びら・落ち葉の埋込画像

- `sakura_petal.png`：桜の花びら1枚。256×256、背景透過。
- `autumn_leaf.png`：落ち葉1枚。256×256、背景透過。
- どちらも `make_sprites.ps1` が輪郭・色面・葉脈を描くイラスト。画像生成AIの出力は使用していない。
- 各素材は1種類だけ。回転・サイズ・傾き・色差は描画時に変えるが、画像のアソートは行わない。

画像を変更する場合は、プロジェクトのルートで次を実行する。

```powershell
.\Assets\Particles\make_sprites.ps1
Push-Location Assets\Particles
try {
    & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\brcc32.exe' '-foParticleFX_Sprites.res' ParticleFX_Sprites.rc
} finally {
    Pop-Location
}
```

PNG・RC・RESを一緒に管理する。RESはビルド時の埋込資源で、実行時キャッシュではない。
通常EXEとプラグインは同じ `ParticleFX_Sprites.pas` を使って自分自身のモジュールからPNGを読む。
配布時に外部PNGを追加する必要はなく、描画処理は一時ファイルやキャッシュファイルを作らない。

元のPNG色を基本にし、色指定時は陰影を残して着色する。色差はメモリ上の17段階で表現し、
用途別の画像数を制限する。Direct2D画像はターゲット破棄時に解放する。

著作権・ライセンスは本プロジェクトと同じGPL-3.0-only。
