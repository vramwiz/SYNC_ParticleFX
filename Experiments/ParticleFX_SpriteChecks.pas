unit ParticleFX_SpriteChecks;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 埋込PNGの輪郭・色・透過と、通常EXE上の接触・蓄積・逆シークを検証する。
// 保存するPNG/GIFは検証用の出力だけで、描画器のキャッシュファイルではない。

interface

uses ParticleFX_Types;

type
  TSpriteCheck = procedure(Condition: Boolean; const Description: string);
  TSpriteSavePNG = procedure(const Name: string; const Pixels: TFXPixels; W, H: Integer);

// COM初期化済みの呼出元で実行し、Checkへ結果を、SavePNGへ検証画像を返す。
procedure RunSpriteChecks(const OutputDir: string; Check: TSpriteCheck;
  SavePNG: TSpriteSavePNG; Animation: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.Win.ComObj,
  Winapi.Windows, Winapi.ActiveX, Winapi.Wincodec,
  Vcl.Graphics, Vcl.Imaging.GIFImg, ParticleFX_Renderer, ParticleFX_Sprites;

function EqualPixels(const A, B: TFXPixels): Boolean;
begin
  Result := (Length(A) = Length(B)) and (Length(A) > 0);
  if Result then Result := CompareMem(@A[0], @B[0], Length(A) * 4);
end;

function CountAlpha(const Pixels: TFXPixels): Integer;
var P: TFXPixelRGBA;
begin
  Result := 0;
  for P in Pixels do if P.A > 0 then Inc(Result);
end;

procedure SpriteAnimation(const OutputDir: string; Check: TSpriteCheck);
const W = 320; H = 360; Frames = 32;
type
  TRow = array[0..W * 8 - 1] of Byte;
  PRow = ^TRow;
var
  R: array[0..1] of TFXRenderer;
  Blank, Pixels: TFXPixels;
  S: TFXSettings;
  GIF, Decoded: TGIFImage;
  Bitmap: TBitmap;
  Frame: TGIFFrame;
  Control: TGIFGraphicControlExtension;
  Loop: TGIFAppExtNSLoop;
  F, Tile, X, Y, I, A, BG, OX: Integer;
  Row: PRow;
begin
  SetLength(Blank, W * H);
  R[0] := TFXRenderer.Create; R[1] := TFXRenderer.Create;
  GIF := TGIFImage.Create; Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(W * 2, H);
    GIF.ColorReduction := rmQuantize; GIF.DitherMode := dmNearest;
    for F := 0 to Frames - 1 do
    begin
      Bitmap.PixelFormat := pf32bit;
      for Tile := 0 to 1 do
      begin
        if Tile = 0 then S := FXComposeSettings(fmPetal, feContinuous, fxmNormal)
        else S := FXComposeSettings(fmLeaf, feContinuous, fxmNormal);
        S.Size := 16; S.Rate := 18; S.FloorEnabled := True; S.FloorPosition := 94;
        S.AccumAmount := 40; S.MaxThickness := 18;
        R[Tile].Render(Blank, W, H, 2 + F * 0.08, S, Pixels);
        OX := Tile * W;
        for Y := 0 to H - 1 do
        begin
          Row := Bitmap.ScanLine[Y];
          for X := 0 to W - 1 do
          begin
            I := Y * W + X; A := Pixels[I].A;
            BG := 32 + ((X div 16 + Y div 16) mod 2) * 12;
            Row[(OX + X) * 4] := (Pixels[I].B * A + (BG + 20) * (255 - A)) div 255;
            Row[(OX + X) * 4 + 1] := (Pixels[I].G * A + (BG + 9) * (255 - A)) div 255;
            Row[(OX + X) * 4 + 2] := (Pixels[I].R * A + BG * (255 - A)) div 255;
            Row[(OX + X) * 4 + 3] := 255;
          end;
        end;
      end;
      Frame := GIF.Add(Bitmap);
      Control := TGIFGraphicControlExtension.Create(Frame); Control.Delay := 8;
    end;
    Loop := TGIFAppExtNSLoop.Create(GIF.Images[0]); Loop.Loops := 0;
    GIF.SaveToFile(TPath.Combine(OutputDir, 'sprite_falling_demo.gif'));
    Decoded := TGIFImage.Create;
    try
      Decoded.LoadFromFile(TPath.Combine(OutputDir, 'sprite_falling_demo.gif'));
      Check((Decoded.Images.Count = Frames) and (Decoded.Width = W * 2) and (Decoded.Height = H),
        'illustrated sprite GIF decodes all 32 falling petal and leaf frames');
    finally Decoded.Free; end;
  finally
    Bitmap.Free; GIF.Free; R[1].Free; R[0].Free;
  end;
end;

procedure RunSpriteChecks(const OutputDir: string; Check: TSpriteCheck;
  SavePNG: TSpriteSavePNG; Animation: Boolean);
const
  W = 256; H = 256;
  Shapes: array[0..1] of TFXShape = (shPetal, shLeaf);
  Styles: array[0..1] of TFXStyle = (fsPetal, fsLeaf);
  Names: array[0..1] of string = ('petal', 'leaf');
  BodyColors: array[0..1] of Cardinal = ($F7B6CE, $D98A3F);
var
  Factory: IWICImagingFactory;
  R, Cold: TFXRenderer;
  S, SavedSettings: TFXSettings;
  Blank, SourcePixels, Pixels, Saved, Other, Resized: TFXPixels;
  ImageWidth, ImageHeight: Cardinal;
  I, J, Opaque, Partial, Body: Integer;
  Valid: Boolean;
  P: TFXPixelRGBA;
  Worker: TThread;
  ThreadError: string;
begin
  OleCheck(CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
    IID_IWICImagingFactory, Factory));
  SetLength(Blank, W * H);
  R := TFXRenderer.Create; Cold := TFXRenderer.Create;
  try
    for I := 0 to High(Shapes) do
    begin
      FXLoadSpritePixels(Factory, Shapes[I], SourcePixels, ImageWidth, ImageHeight);
      Check((ImageWidth = 256) and (ImageHeight = 256), Names[I] + ': embedded PNG has the specified 256px size');
      Opaque := 0; Partial := 0; Valid := True;
      for J := 0 to High(SourcePixels) do
      begin
        P := SourcePixels[J];
        if P.A = 255 then Inc(Opaque);
        if (P.A > 0) and (P.A < 255) then Inc(Partial);
        if ((J mod W < 8) or (J mod W > W - 9) or (J div W < 8) or (J div W > H - 9)) and
          (P.A <> 0) then Valid := False;
      end;
      Check(Valid and (Opaque > 10000) and (Partial > 100),
        Names[I] + ': PNG has transparent padding, an opaque body and antialiased edges');
      if I = 0 then
        Check((SourcePixels[40 * W + 128].A = 0) and (SourcePixels[40 * W + 88].A > 250),
          'sakura PNG keeps a visible notch between the two rounded lobes')
      else
        Check((SourcePixels[90 * W + 125].R > SourcePixels[90 * W + 115].R + 10) and
          (SourcePixels[234 * W + 129].A > 0), 'leaf PNG contains a contrasting midrib and a thin petiole');

      S := FXDefaultSettings(Styles[I]);
      S.Emission := feShot; S.Burst := 1; S.EmitterRange := 0;
      S.AutomaticEmitter := False; S.AutomaticLifetime := False; S.Lifetime := 8;
      S.Speed := 0; S.Gravity := 0; S.Sway := 0; S.Size := 70;
      S.SizeVariation := 0; S.Depth := 0; S.ColorVariation := 0;
      S.Opacity := 1; S.Rotation := 0; S.Collision := False; S.Accumulation := False;
      R.Render(Blank, W, H, 0.5, S, Saved);
      Body := 0;
      for P in Saved do
        if (P.A > 250) and (Abs(P.R - Integer((BodyColors[I] shr 16) and 255)) <= 2) and
          (Abs(P.G - Integer((BodyColors[I] shr 8) and 255)) <= 2) and
          (Abs(P.B - Integer(BodyColors[I] and 255)) <= 2) then Inc(Body);
      Check(Body > 500, Names[I] + ': renderer draws the actual illustrated PNG palette');
      SavePNG('sprite_' + Names[I] + '_closeup', Saved, W, H);

      S.CustomColor := True; S.Color := $00D060;
      R.Render(Blank, W, H, 0.5, S, Pixels);
      Valid := True; Body := 0;
      for J := 0 to High(Pixels) do
      begin
        if Pixels[J].A <> Saved[J].A then Valid := False;
        if (Pixels[J].A > 250) and (Pixels[J].G > Pixels[J].R + 20) then Inc(Body);
      end;
      Check(Valid and (Body > 500), Names[I] + ': custom tint preserves the exact PNG alpha');
      S.CustomColor := False; S.Color := FXProfile(Styles[I]).Color;
      R.Render(Blank, W, H, 0.5, S, Other);
      Check(EqualPixels(Saved, Other), Names[I] + ': restoring original colors leaves no previous tint');

      S.ColorVariation := 0.8; S.Rotation := 75;
      R.Render(Blank, W, H, 0.75, S, Saved);
      R.Render(Blank, W, H, 1.3, S, Other);
      R.Render(Blank, W, H, 0.75, S, Other);
      Cold.Render(Blank, W, H, 0.75, S, Pixels);
      Check(EqualPixels(Saved, Other) and EqualPixels(Saved, Pixels),
        Names[I] + ': rotation and color variation reproduce reverse seek and a cold renderer');
      SetLength(Resized, 320 * 240);
      R.Render(Resized, 320, 240, 0.75, S, Pixels);
      R.Render(Blank, W, H, 0.75, S, Other);
      Check(EqualPixels(Saved, Other), Names[I] + ': resizing recreates target-owned sprite images correctly');

      S.Collision := True; S.FloorEnabled := True; S.FloorPosition := 60;
      S.EmitterY := -80; S.Speed := 180; S.DirectionSpread := 0; S.Angle := 0;
      S.Size := 14; S.Response := 2; S.ContactLife := 4; S.DrawMode := 2;
      R.Render(Blank, W, H, 0.9, S, Pixels);
      Check((R.Stats.Contacts > 0) and (CountAlpha(Pixels) > 50),
        Names[I] + ': floor contact retains the PNG in contact-only output');
      SavePNG('sprite_' + Names[I] + '_contact', Pixels, W, H);
      S.Rate := 0; S.Burst := 0; S.Accumulation := True; S.AccumAmount := 70; S.MaxThickness := 22;
      R.Render(Blank, W, H, 2, S, Pixels);
      Check(CountAlpha(Pixels) > 50, Names[I] + ': accumulation draws overlapping PNG pieces');
      SavePNG('sprite_' + Names[I] + '_accumulation', Pixels, W, H);
      S.CustomAccumColor := True; S.AccumColor := $4080FF;
      R.Render(Blank, W, H, 2, S, Other);
      Valid := True;
      for J := 0 to High(Pixels) do if Pixels[J].A <> Other[J].A then Valid := False;
      Check(Valid and not EqualPixels(Pixels, Other), Names[I] + ': separate accumulation tint retains PNG alpha');
      S.AccumAmount := 0;
      R.Render(Blank, W, H, 2, S, Pixels);
      Check(CountAlpha(Pixels) = 0, Names[I] + ': zero accumulation clears previous PNG pieces');

      S := FXComposeSettings(TFXMaterial(Ord(fmPetal) + I), feContinuous, fxmNormal);
      SetLength(Resized, 960 * 540);
      R.Render(Resized, 960, 540, 2, S, Saved);
      SavePNG('sprite_' + Names[I] + '_falling', Saved, 960, 540);
      SavedSettings := S; ThreadError := '';
      Worker := TThread.CreateAnonymousThread(
        procedure
        var HR: HRESULT;
        begin
          HR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
          try
            try R.Render(Resized, 960, 540, 2, SavedSettings, Other);
            except on E: Exception do ThreadError := E.Message; end;
          finally if Succeeded(HR) then CoUninitialize; end;
        end);
      Worker.FreeOnTerminate := False;
      try Worker.Start; Worker.WaitFor; finally Worker.Free; end;
      R.Render(Resized, 960, 540, 2, S, Pixels);
      Check((ThreadError = '') and EqualPixels(Saved, Other) and EqualPixels(Saved, Pixels),
        Names[I] + ': embedded sprites survive STA rendering and apartment teardown');
      Check(CountAlpha(Blank) = 0, Names[I] + ': sprite rendering preserves the transparent input');
    end;
    if Animation then SpriteAnimation(OutputDir, Check);
  finally Cold.Free; R.Free; end;
end;

end.
