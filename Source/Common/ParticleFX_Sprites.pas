unit ParticleFX_Sprites;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 事前作成した1種類ずつの透過PNGをモジュール資源から読み、粒子の画像として描く。
// 復号画素と上限付きの色調画像をメモリだけに保持し、ファイルを読み書きしない。
// Direct2D画像の所有期間は描画ターゲットまで。復号済み画素はCOMに依存しない。

interface

uses
  Winapi.D2D1, Winapi.Wincodec, ParticleFX_Types;

// 呼出側のCOM初期化とWICを使用し、埋込PNGのストレートRGBAを値で返す。
// Shapeは花びら・落ち葉のみ。画像は実行モジュールの資源から読み込む。
procedure FXLoadSpritePixels(const Factory: IWICImagingFactory; Shape: TFXShape;
  out Pixels: TFXPixels; out Width, Height: Cardinal);

type
  TFXSpriteLibrary = class
  private type
    TTones = record
      Color: Cardinal;
      CustomColor, Prepared: Boolean;
      Bitmaps: array[0..16] of ID2D1Bitmap;
    end;
    TImage = record
      Pixels: TFXPixels;
      Width, Height: Cardinal;
      Tones: array[Boolean] of TTones;
    end;
  private
    FImages: array[0..1] of TImage;
  public
    // ターゲット破棄・スレッド交代時に呼び、COM資源だけを解放する。
    procedure ResetTarget;
    // 現在の変換行列で中心原点の画像を描く。ターゲットは呼出側が直列化する。
    // Accumulatedは蓄積の別色指定を選ぶ。色調は最大17段階×2用途×2素材に制限する。
    procedure Draw(const Target: ID2D1RenderTarget; const Factory: IWICImagingFactory;
      const Visual: TFXVisual; const Settings: TFXSettings; Accumulated: Boolean);
  end;

implementation

uses
  System.Math, System.SysUtils, System.Win.ComObj, Winapi.Windows, Winapi.ActiveX,
  Winapi.DxgiFormat;

{$R '..\..\Assets\Particles\ParticleFX_Sprites.res' '..\..\Assets\Particles\ParticleFX_Sprites.rc'}

procedure FXLoadSpritePixels(const Factory: IWICImagingFactory; Shape: TFXShape;
  out Pixels: TFXPixels; out Width, Height: Cardinal);
var
  Name: PWideChar;
  Module: HMODULE;
  Resource: HRSRC;
  Data: HGLOBAL;
  Stream: IWICStream;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Converter: IWICFormatConverter;
begin
  case Shape of
    shPetal: Name := 'PFX_SAKURA_PETAL';
    shLeaf: Name := 'PFX_AUTUMN_LEAF';
  else
    raise EArgumentException.Create('PNG素材の形が不正です。');
  end;
  // EXE・DLLのどちらでも、この処理を含むモジュールを明示する。
  Module := FindHInstance(@FXLoadSpritePixels);
  Resource := FindResource(Module, Name, RT_RCDATA);
  if Resource = 0 then RaiseLastOSError;
  Data := LoadResource(Module, Resource);
  if Data = 0 then RaiseLastOSError;
  OleCheck(Factory.CreateStream(Stream));
  // 資源のメモリはモジュールが所有し、復号終了より長く存続する。
  OleCheck(Stream.InitializeFromMemory(LockResource(Data), SizeofResource(Module, Resource)));
  OleCheck(Factory.CreateDecoderFromStream(Stream, GUID_NULL, WICDecodeMetadataCacheOnLoad, Decoder));
  OleCheck(Decoder.GetFrame(0, Frame));
  OleCheck(Frame.GetSize(Width, Height));
  if (Width <> 256) or (Height <> 256) then
    raise EInvalidOp.Create('PNG素材は256×256で作成してください。');
  OleCheck(Factory.CreateFormatConverter(Converter));
  OleCheck(Converter.Initialize(Frame, GUID_WICPixelFormat32bppRGBA, WICBitmapDitherTypeNone,
    nil, 0, WICBitmapPaletteTypeCustom));
  SetLength(Pixels, Width * Height);
  OleCheck(Converter.CopyPixels(nil, Width * 4, Length(Pixels) * 4, @Pixels[0]));
end;

procedure TFXSpriteLibrary.ResetTarget;
var
  I, J: Integer;
  Accumulated: Boolean;
begin
  for I := Low(FImages) to High(FImages) do
    for Accumulated := False to True do
    begin
      for J := Low(FImages[I].Tones[Accumulated].Bitmaps) to
        High(FImages[I].Tones[Accumulated].Bitmaps) do
        FImages[I].Tones[Accumulated].Bitmaps[J] := nil;
      FImages[I].Tones[Accumulated].Prepared := False;
    end;
end;

procedure TFXSpriteLibrary.Draw(const Target: ID2D1RenderTarget;
  const Factory: IWICImagingFactory; const Visual: TFXVisual;
  const Settings: TFXSettings; Accumulated: Boolean);
var
  ImageIndex, Tone, I, J, A, Luminance: Integer;
  Color: Cardinal;
  CustomColor: Boolean;
  Factor, Denominator, Numerator: Double;
  Pixels: TArray<Byte>;
  P: TFXPixelRGBA;
  Properties: TD2D1BitmapProperties;
  Bounds: TD2D1RectF;
  Image: ^TImage;
  Bank: ^TTones;
begin
  if Visual.Shape = shPetal then ImageIndex := 0
  else if Visual.Shape = shLeaf then ImageIndex := 1
  else raise EArgumentException.Create('PNG素材の形が不正です。');
  Image := @FImages[ImageIndex];
  if Length(Image^.Pixels) = 0 then
    FXLoadSpritePixels(Factory, Visual.Shape, Image^.Pixels, Image^.Width, Image^.Height);
  Color := Settings.Color; CustomColor := Settings.CustomColor;
  if Accumulated and Settings.CustomAccumColor then
  begin
    Color := Settings.AccumColor; CustomColor := True;
  end;
  Bank := @Image^.Tones[Accumulated];
  if not Bank^.Prepared or (Bank^.Color <> Color) or (Bank^.CustomColor <> CustomColor) then
  begin
    for J := Low(Bank^.Bitmaps) to High(Bank^.Bitmaps) do Bank^.Bitmaps[J] := nil;
    Bank^.Color := Color; Bank^.CustomColor := CustomColor; Bank^.Prepared := True;
  end;
  // 粒子ごとの色差は明るさだけなので、画像を無制限に作らず固定17段階へ丸める。
  Denominator := ((Color shr 16) and 255) + ((Color shr 8) and 255) + (Color and 255);
  Numerator := ((Visual.Color shr 16) and 255) + ((Visual.Color shr 8) and 255) + (Visual.Color and 255);
  Factor := 1;
  if Denominator > 0 then Factor := Numerator / Denominator;
  Tone := EnsureRange(Round((Factor - 0.5) * 16), 0, 16);
  if Bank^.Bitmaps[Tone] = nil then
  begin
    Factor := 0.5 + Tone / 16;
    SetLength(Pixels, Length(Image^.Pixels) * 4);
    for I := 0 to High(Image^.Pixels) do
    begin
      P := Image^.Pixels[I]; A := P.A;
      if CustomColor then
      begin
        // 元画像の色相を置き換えても、葉脈とイラストの明暗は残す。
        Luminance := (Integer(P.R) * 54 + Integer(P.G) * 183 + Integer(P.B) * 19) div 256;
        P.R := Round(((Color shr 16) and 255) * (0.4 + 0.6 * Luminance / 255));
        P.G := Round(((Color shr 8) and 255) * (0.4 + 0.6 * Luminance / 255));
        P.B := Round((Color and 255) * (0.4 + 0.6 * Luminance / 255));
      end;
      Pixels[I * 4] := Min(255, Round(P.B * Factor)) * A div 255;
      Pixels[I * 4 + 1] := Min(255, Round(P.G * Factor)) * A div 255;
      Pixels[I * 4 + 2] := Min(255, Round(P.R * Factor)) * A div 255;
      Pixels[I * 4 + 3] := A;
    end;
    Properties := D2D1BitmapProperties(
      D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
    OleCheck(Target.CreateBitmap(D2D1SizeU(Image^.Width, Image^.Height), @Pixels[0],
      Image^.Width * 4, Properties, Bank^.Bitmaps[Tone]));
  end;
  Bounds := D2D1RectF(-1.4, -1.4, 1.4, 1.4);
  Target.DrawBitmap(Bank^.Bitmaps[Tone], @Bounds, EnsureRange(Visual.Opacity, 0.0, 1.0));
end;

end.
