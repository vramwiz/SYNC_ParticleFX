unit ParticleFX_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// Direct2Dで透過WIC面へ描き、PBGRAからストレートRGBAへ合成する。
// 元画像・接触マスク・透過描画面を分離し、入力バッファは変更しない。
// 粘性粒子は密度場で面をつなぎ、同じRGBA合成と下余白へ接続する。

interface

uses
  Winapi.D2D1, Winapi.Wincodec, ParticleFX_Types, ParticleFX_Collision,
  ParticleFX_Simulation, ParticleFX_Viscous;

type
  TFXFluidCell = record
    Density, R, G, B: Single;
  end;
  TFXRenderStats = record
    VisibleParticles, Contacts, SimulatedSteps, Surfaces: Integer;
    ContourRevision: Integer;
    MaskMS, ResourceMS, SimulationMS, DrawingMS, CompositeMS: Double;
  end;

  TFXRenderer = class
  private
    FFactory: ID2D1Factory;
    FWicFactory: IWICImagingFactory;
    FBitmap: IWICBitmap;
    FTarget: ID2D1RenderTarget;
    FBrush: ID2D1SolidColorBrush;
    FSoftBrush: ID2D1RadialGradientBrush;
    FRoundStroke: ID2D1StrokeStyle;
    FPetal, FLeaf, FAccumulation, FAccumEdge: ID2D1PathGeometry;
    FEnvironment: TFXEnvironment;
    FSimulator: TFXSimulator;
    FViscous: TFXViscousFlow;
    FVisuals: TFXVisualList;
    FOverlay: TArray<Byte>;
    FFluidField: TArray<TFXFluidCell>;
    FExpandedInput: TFXPixels;
    FOutputWidth, FOutputHeight: Integer;
    FWidth, FHeight, FAccumRevision: Integer;
    FSoftColor: Cardinal;
    FMTACookie: Pointer;
    FStats: TFXRenderStats;
    procedure EnsureResources(Width, Height: Integer);
    procedure ResetTarget;
    procedure ResetGraphics;
    procedure SetColor(Color: Cardinal; Opacity: Double);
    procedure UpdateSoftColor(Color: Cardinal);
    procedure DrawVisual(const V: TFXVisual; const S: TFXSettings);
    procedure BuildAccumulation;
    procedure DrawAccumulation(const S: TFXSettings);
    procedure DrawViscousField(const S: TFXSettings);
    procedure Composite(const Input: TFXPixels; out Output: TFXPixels; ClearInput: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    // 同一インスタンスの呼出は呼出側で直列化する。全リソースを自身が所有する。
    // 任意時刻の透過RGBAをOutputへ返し、Inputを保持・書き換えない。
    procedure Render(const Input: TFXPixels; Width, Height: Integer;
      Time: Double; const Settings: TFXSettings; out Output: TFXPixels);
    property Stats: TFXRenderStats read FStats;
    property OutputWidth: Integer read FOutputWidth;
    property OutputHeight: Integer read FOutputHeight;
  end;

implementation

uses
  System.Math, System.SysUtils, System.Win.ComObj, System.Diagnostics,
  Winapi.Windows, Winapi.ActiveX, Winapi.DxgiFormat;

// Windows 10以降で提供される公式COM API。cookieの解放は別スレッドでも可能。
function FXCoIncrementMTAUsage(out Cookie: Pointer): HRESULT; stdcall;
  external 'ole32.dll' name 'CoIncrementMTAUsage';
function FXCoDecrementMTAUsage(Cookie: Pointer): HRESULT; stdcall;
  external 'ole32.dll' name 'CoDecrementMTAUsage';

constructor TFXRenderer.Create;
begin
  inherited;
  OleCheck(FXCoIncrementMTAUsage(FMTACookie));
  FEnvironment := TFXEnvironment.Create;
  FSimulator := TFXSimulator.Create;
  FVisuals := TFXVisualList.Create;
  FAccumRevision := -1;
end;

destructor TFXRenderer.Destroy;
begin
  ResetGraphics;
  FViscous.Free; FVisuals.Free; FSimulator.Free; FEnvironment.Free;
  if FMTACookie <> nil then FXCoDecrementMTAUsage(FMTACookie);
  inherited;
end;

procedure TFXRenderer.ResetGraphics;
begin
  ResetTarget;
  FPetal := nil; FLeaf := nil; FRoundStroke := nil;
  FAccumulation := nil; FAccumEdge := nil; FAccumRevision := -1;
  FFactory := nil; FWicFactory := nil;
end;

procedure TFXRenderer.ResetTarget;
begin
  FSoftBrush := nil; FBrush := nil; FTarget := nil; FBitmap := nil;
  FWidth := 0; FHeight := 0;
end;

procedure TFXRenderer.EnsureResources(Width, Height: Integer);
var
  Properties: TD2D1RenderTargetProperties;
  Stroke: TD2D1StrokeStyleProperties;
  Sink: ID2D1GeometrySink;
  Bezier: TD2D1BezierSegment;
begin
  if FFactory = nil then
  begin
    OleCheck(D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED, ID2D1Factory, nil, FFactory));
    OleCheck(CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
      IID_IWICImagingFactory, FWicFactory));
    Stroke := D2D1StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
      D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND);
    OleCheck(FFactory.CreateStrokeStyle(Stroke, nil, 0, FRoundStroke));
    OleCheck(FFactory.CreatePathGeometry(FPetal));
    OleCheck(FPetal.Open(Sink));
    Sink.BeginFigure(D2D1PointF(0, -0.9), D2D1_FIGURE_BEGIN_FILLED);
    Bezier.point1 := D2D1PointF(-1.25, -1.2); Bezier.point2 := D2D1PointF(-1.05, 0.6);
    Bezier.point3 := D2D1PointF(0, 1.15); Sink.AddBezier(Bezier);
    Bezier.point1 := D2D1PointF(1.05, 0.6); Bezier.point2 := D2D1PointF(1.25, -1.2);
    Bezier.point3 := D2D1PointF(0, -0.9); Sink.AddBezier(Bezier);
    Sink.EndFigure(D2D1_FIGURE_END_CLOSED); OleCheck(Sink.Close); Sink := nil;
    OleCheck(FFactory.CreatePathGeometry(FLeaf));
    OleCheck(FLeaf.Open(Sink));
    Sink.BeginFigure(D2D1PointF(0, -1.3), D2D1_FIGURE_BEGIN_FILLED);
    Bezier.point1 := D2D1PointF(-1.2, -0.4); Bezier.point2 := D2D1PointF(-0.7, 0.8);
    Bezier.point3 := D2D1PointF(0, 1.3); Sink.AddBezier(Bezier);
    Bezier.point1 := D2D1PointF(0.7, 0.8); Bezier.point2 := D2D1PointF(1.2, -0.4);
    Bezier.point3 := D2D1PointF(0, -1.3); Sink.AddBezier(Bezier);
    Sink.EndFigure(D2D1_FIGURE_END_CLOSED); OleCheck(Sink.Close);
  end;
  if (FTarget <> nil) and (Width = FWidth) and (Height = FHeight) then Exit;
  ResetTarget;
  OleCheck(FWicFactory.CreateBitmap(Width, Height, @GUID_WICPixelFormat32bppPBGRA,
    WICBitmapCacheOnLoad, FBitmap));
  Properties := D2D1RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_SOFTWARE,
    D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
  OleCheck(FFactory.CreateWicBitmapRenderTarget(FBitmap, Properties, FTarget));
  FTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  OleCheck(FTarget.CreateSolidColorBrush(D2D1ColorF(1, 1, 1, 1), nil, FBrush));
  UpdateSoftColor($FFFFFF);
  FWidth := Width; FHeight := Height;
  SetLength(FOverlay, Width * Height * 4);
end;

procedure TFXRenderer.UpdateSoftColor(Color: Cardinal);
var
  Stops: array[0..2] of TD2D1GradientStop;
  StopCollection: ID2D1GradientStopCollection;
  R, G, B: Single;
begin
  if (FSoftBrush <> nil) and (FSoftColor = Color) then Exit;
  R := ((Color shr 16) and 255) / 255;
  G := ((Color shr 8) and 255) / 255;
  B := (Color and 255) / 255;
  Stops[0] := D2D1GradientStop(0, D2D1ColorF(R, G, B, 1));
  Stops[1] := D2D1GradientStop(0.48, D2D1ColorF(R, G, B, 0.82));
  Stops[2] := D2D1GradientStop(1, D2D1ColorF(R, G, B, 0));
  OleCheck(FTarget.CreateGradientStopCollection(@Stops[0], Length(Stops),
    D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP, StopCollection));
  OleCheck(FTarget.CreateRadialGradientBrush(D2D1RadialGradientBrushProperties(
    D2D1PointF(0, 0), D2D1PointF(-0.2, -0.2), 1, 1), nil, StopCollection, FSoftBrush));
  FSoftColor := Color;
end;

procedure TFXRenderer.SetColor(Color: Cardinal; Opacity: Double);
begin
  FBrush.SetColor(D2D1ColorF(((Color shr 16) and 255) / 255,
    ((Color shr 8) and 255) / 255, (Color and 255) / 255, EnsureRange(Opacity, 0.0, 1.0)));
end;

procedure TFXRenderer.DrawVisual(const V: TFXVisual; const S: TFXSettings);
var
  Matrix: TD2D1Matrix3x2F;
  Radius, CS, SN, Flip, Speed, Trail, DX, DY: Single;
begin
  if V.Opacity <= 0 then Exit;
  Radius := V.Size;
  if (V.Position.X < -Radius * 8) or (V.Position.Y < -Radius * 8) or
    (V.Position.X > FWidth + Radius * 8) or (V.Position.Y > FHeight + Radius * 8) then Exit;
  FTarget.SetTransform(TD2D1Matrix3x2F.Identity);
  if (S.Glow > 0) or (V.Shape = shLight) then
  begin
    FSoftBrush.SetCenter(D2D1PointF(V.Position.X, V.Position.Y));
    FSoftBrush.SetRadiusX(Radius * 4); FSoftBrush.SetRadiusY(Radius * 4);
    FSoftBrush.SetOpacity(Min(0.8, V.Opacity * (0.2 + S.Glow * 0.3)));
    FTarget.FillEllipse(D2D1Ellipse(D2D1PointF(V.Position.X, V.Position.Y), Radius * 4, Radius * 4), FSoftBrush);
  end;
  SetColor(V.Color, V.Opacity);
  case V.Shape of
    shDrop: begin
      Speed := Max(1, FXLength(V.Velocity));
      DX := V.Velocity.X / Speed; DY := V.Velocity.Y / Speed;
      Trail := Min(60.0, Speed * (0.006 + 0.025 * S.MotionBlur));
      if V.IsSplash then Trail := Min(Trail, Radius * 2.5);
      if S.Style in [fsWater, fsFountain] then Trail := Min(Trail, Radius * 4);
      FTarget.DrawLine(D2D1PointF(V.Position.X - DX * Trail, V.Position.Y - DY * Trail),
        D2D1PointF(V.Position.X, V.Position.Y), FBrush, Max(0.6, Radius * 0.85), FRoundStroke);
      if Radius > 2 then
      begin
        SetColor($FFFFFF, V.Opacity * 0.7);
        FTarget.FillEllipse(D2D1Ellipse(D2D1PointF(V.Position.X - Radius * 0.2,
          V.Position.Y - Radius * 0.3), Radius * 0.23, Radius * 0.23), FBrush);
      end;
    end;
    shSnow: begin
      // 広い弱い外周と小さい芯で、透明背景でも暗い縁を作らず柔らかくする。
      FSoftBrush.SetCenter(D2D1PointF(V.Position.X, V.Position.Y));
      FSoftBrush.SetRadiusX(Radius * (1.15 + S.Blur * 0.25));
      FSoftBrush.SetRadiusY(Radius * V.Aspect * (1.15 + S.Blur * 0.25));
      FSoftBrush.SetOpacity(V.Opacity);
      FTarget.FillEllipse(D2D1Ellipse(D2D1PointF(V.Position.X, V.Position.Y),
        Radius * (1.15 + S.Blur * 0.25), Radius * V.Aspect * (1.15 + S.Blur * 0.25)), FSoftBrush);
      SetColor(V.Color, V.Opacity * 0.7);
      FTarget.FillEllipse(D2D1Ellipse(D2D1PointF(V.Position.X, V.Position.Y),
        Radius * 0.42, Radius * 0.42 * V.Aspect), FBrush);
    end;
    shPetal, shLeaf, shPaper: begin
      CS := Cos(V.Angle); SN := Sin(V.Angle);
      Flip := 0.3 + 0.7 * Abs(Cos(V.Angle * 0.7));
      Matrix._11 := CS * Radius * Flip; Matrix._12 := SN * Radius * Flip;
      Matrix._21 := -SN * Radius * V.Aspect; Matrix._22 := CS * Radius * V.Aspect;
      Matrix._31 := V.Position.X; Matrix._32 := V.Position.Y;
      FTarget.SetTransform(Matrix);
      case V.Shape of
        shPetal: FTarget.FillGeometry(FPetal, FBrush);
        shLeaf: FTarget.FillGeometry(FLeaf, FBrush);
        shPaper: FTarget.FillRectangle(D2D1RectF(-0.6, -1, 0.6, 1), FBrush);
      end;
      SetColor($FFFFFF, V.Opacity * 0.25);
      FTarget.DrawLine(D2D1PointF(0, -0.6), D2D1PointF(0, 0.8), FBrush, 0.09);
      FTarget.SetTransform(TD2D1Matrix3x2F.Identity);
    end;
    shGrain, shHail, shLight, shInk: begin
      FTarget.FillEllipse(D2D1Ellipse(D2D1PointF(V.Position.X, V.Position.Y),
        Radius, Radius * V.Aspect), FBrush);
      if V.Shape in [shHail, shLight] then
      begin
        SetColor($FFFFFF, V.Opacity * 0.8);
        FTarget.FillEllipse(D2D1Ellipse(D2D1PointF(V.Position.X - Radius * 0.25,
          V.Position.Y - Radius * 0.25), Radius * 0.35, Radius * 0.35), FBrush);
      end;
    end;
  end;
end;

procedure TFXRenderer.BuildAccumulation;
var
  Sink, EdgeSink: ID2D1GeometrySink;
  I, J, K: Integer;
  A, B: TFXSurface;
begin
  if FAccumRevision = FEnvironment.Revision then Exit;
  FAccumulation := nil; FAccumEdge := nil;
  OleCheck(FFactory.CreatePathGeometry(FAccumulation)); OleCheck(FAccumulation.Open(Sink));
  OleCheck(FFactory.CreatePathGeometry(FAccumEdge)); OleCheck(FAccumEdge.Open(EdgeSink));
  I := 0;
  while I < FEnvironment.SurfaceCount do
  begin
    A := FEnvironment.Surfaces[I];
    if not A.Valid then begin Inc(I); Continue; end;
    J := I;
    while J + 1 < FEnvironment.SurfaceCount do
    begin
      A := FEnvironment.Surfaces[J]; B := FEnvironment.Surfaces[J + 1];
      if not B.Valid or (Sqr(A.Base.X - B.Base.X) + Sqr(A.Base.Y - B.Base.Y) > 100) then Break;
      Inc(J);
    end;
    A := FEnvironment.Surfaces[I];
    if I = J then
    begin
      // 1px幅の輪郭にも面積のある小さな帽子を作り、見えない接触面を残さない。
      Sink.BeginFigure(D2D1PointF(A.Tip.X + A.Normal.Y * 1.2,
        A.Tip.Y - A.Normal.X * 1.2), D2D1_FIGURE_BEGIN_FILLED);
      EdgeSink.BeginFigure(D2D1PointF(A.Tip.X + A.Normal.Y * 1.2,
        A.Tip.Y - A.Normal.X * 1.2), D2D1_FIGURE_BEGIN_HOLLOW);
      Sink.AddLine(D2D1PointF(A.Tip.X - A.Normal.Y * 1.2, A.Tip.Y + A.Normal.X * 1.2));
      EdgeSink.AddLine(D2D1PointF(A.Tip.X - A.Normal.Y * 1.2, A.Tip.Y + A.Normal.X * 1.2));
      Sink.AddLine(D2D1PointF(A.Base.X - A.Normal.Y * 1.2 - A.Normal.X * 1.2,
        A.Base.Y + A.Normal.X * 1.2 - A.Normal.Y * 1.2));
      Sink.AddLine(D2D1PointF(A.Base.X + A.Normal.Y * 1.2 - A.Normal.X * 1.2,
        A.Base.Y - A.Normal.X * 1.2 - A.Normal.Y * 1.2));
      Sink.EndFigure(D2D1_FIGURE_END_CLOSED); EdgeSink.EndFigure(D2D1_FIGURE_END_OPEN);
      Inc(I);
      Continue;
    end;
    Sink.BeginFigure(D2D1PointF(A.Tip.X, A.Tip.Y), D2D1_FIGURE_BEGIN_FILLED);
    EdgeSink.BeginFigure(D2D1PointF(A.Tip.X, A.Tip.Y), D2D1_FIGURE_BEGIN_HOLLOW);
    for K := I + 1 to J do
    begin
      A := FEnvironment.Surfaces[K];
      Sink.AddLine(D2D1PointF(A.Tip.X, A.Tip.Y));
      EdgeSink.AddLine(D2D1PointF(A.Tip.X, A.Tip.Y));
    end;
    for K := J downto I do
    begin
      A := FEnvironment.Surfaces[K];
      Sink.AddLine(D2D1PointF(A.Base.X - A.Normal.X * 1.2, A.Base.Y - A.Normal.Y * 1.2));
    end;
    Sink.EndFigure(D2D1_FIGURE_END_CLOSED); EdgeSink.EndFigure(D2D1_FIGURE_END_OPEN);
    I := J + 1;
  end;
  OleCheck(Sink.Close); OleCheck(EdgeSink.Close);
  FAccumRevision := FEnvironment.Revision;
end;

procedure TFXRenderer.DrawAccumulation(const S: TFXSettings);
var
  I, J, Layers: Integer;
  Surface: TFXSurface;
  V: TFXVisual;
  MaterialSettings: TFXSettings;
  ID: Int64;
  Depth, Across, BaseOpacity: Double;
begin
  if FEnvironment.SurfaceCount = 0 then Exit;
  BuildAccumulation;
  FTarget.SetTransform(TD2D1Matrix3x2F.Identity);
  BaseOpacity := S.AccumOpacity;
  if S.Style in [fsPetal, fsLeaf, fsConfetti] then BaseOpacity := BaseOpacity * 0.55;
  SetColor(S.AccumColor, BaseOpacity);
  FTarget.FillGeometry(FAccumulation, FBrush);
  SetColor($FFFFFF, BaseOpacity * 0.4);
  FTarget.DrawGeometry(FAccumEdge, FBrush, 1.2, FRoundStroke);
  if not (S.Style in [fsPetal, fsLeaf, fsConfetti, fsSand, fsHail]) then Exit;
  // 蓄積量は履歴ではなく、固定した素材片の位置・数へ反映する。
  MaterialSettings := S; MaterialSettings.Glow := 0; MaterialSettings.MotionBlur := 0;
  I := 0;
  while I < FEnvironment.SurfaceCount do
  begin
    Surface := FEnvironment.Surfaces[I];
    if Surface.Valid and (Surface.Thickness > 1) then
    begin
      Layers := Min(8, Max(1, Ceil(Surface.Thickness / Max(2.0, S.Size * 0.8))));
      for J := 0 to Layers - 1 do
      begin
        ID := Int64(I) * 17 + J;
        V := Default(TFXVisual);
        V.Size := Min(4.5, Max(0.7, S.Size * 0.55)) * (0.7 + FXRandom(ID, S.Seed, 151) * 0.5);
        V.Size := Min(V.Size, Max(0.8, Surface.Thickness * 0.45));
        Depth := Surface.Thickness * (J + 0.3 + FXRandom(ID, S.Seed, 152) * 0.4) / Layers;
        Across := (FXRandom(ID, S.Seed, 153) - 0.5) * 2;
        V.Position := FXVec(Surface.Base.X + Surface.Normal.X * Depth - Surface.Normal.Y * Across,
          Surface.Base.Y + Surface.Normal.Y * Depth + Surface.Normal.X * Across);
        V.Color := FXParticleColor(S, ID);
        if S.CustomAccumColor then V.Color := S.AccumColor;
        V.Opacity := S.AccumOpacity * (0.6 + FXRandom(ID, S.Seed, 154) * 0.4);
        V.Angle := FXRandom(ID, S.Seed, 155) * 2 * Pi;
        V.Aspect := S.Aspect; V.Shape := S.Shape;
        DrawVisual(V, MaterialSettings);
      end;
    end;
    Inc(I, 3);
  end;
end;

procedure TFXRenderer.Composite(const Input: TFXPixels; out Output: TFXPixels; ClearInput: Boolean);
var
  I, A, DA, OA, Inv, R, G, B: Integer;
begin
  SetLength(Output, Length(Input));
  if ClearInput then FillChar(Output[0], Length(Output) * SizeOf(TFXPixelRGBA), 0)
  else Move(Input[0], Output[0], Length(Input) * SizeOf(TFXPixelRGBA));
  for I := 0 to High(Output) do
  begin
    A := FOverlay[I * 4 + 3];
    if A = 0 then Continue;
    DA := Output[I].A; Inv := 255 - A;
    OA := A + (DA * Inv + 127) div 255;
    R := FOverlay[I * 4 + 2] * 255 + (Output[I].R * DA * Inv + 127) div 255;
    G := FOverlay[I * 4 + 1] * 255 + (Output[I].G * DA * Inv + 127) div 255;
    B := FOverlay[I * 4] * 255 + (Output[I].B * DA * Inv + 127) div 255;
    Output[I].R := Min(255, (R + OA div 2) div OA);
    Output[I].G := Min(255, (G + OA div 2) div OA);
    Output[I].B := Min(255, (B + OA div 2) div OA);
    Output[I].A := OA;
  end;
end;

procedure TFXRenderer.DrawViscousField(const S: TFXSettings);
var
  FW, FH, I, X, Y, X0, X1, Y0, Y1, IX, IY, PX, PY, A: Integer;
  V: TFXVisual;
  R, RX, RY, DX, DY, CS, SN, Q, W, Extent, Density, Cover, Light, Shine,
    Red, Green, Blue, FX, FY, TX, TY, NX, NY: Double;
  C, C00, C10, C01, C11: TFXFluidCell;
  function Mix(A, B, C, D: Single): Double;
  begin
    Result := (A * (1 - TX) + B * TX) * (1 - TY) + (C * (1 - TX) + D * TX) * TY;
  end;
begin
  // 半解像度の密度場へ粒を加算し、等密度面で一つの液体として描く。
  // 粒の重なりに輪郭線を残さず、透明な細い首や滴下をつなぐ。
  FW := (FWidth + 1) div 2; FH := (FHeight + 1) div 2;
  SetLength(FFluidField, FW * FH);
  FillChar(FFluidField[0], Length(FFluidField) * SizeOf(TFXFluidCell), 0);
  for I := 0 to FVisuals.Count - 1 do
  begin
    V := FVisuals[I];
    if (V.Opacity <= 0) or ((S.DrawMode = 2) and not V.IsSplash) then Continue;
    R := Max(1.2, V.Size * (1.25 + S.Cohesion * 0.5));
    RX := R; RY := R * V.Aspect; Extent := Max(RX, RY);
    X0 := Max(0, Floor((V.Position.X - Extent) * 0.5));
    X1 := Min(FW - 1, Ceil((V.Position.X + Extent) * 0.5));
    Y0 := Max(0, Floor((V.Position.Y - Extent) * 0.5));
    Y1 := Min(FH - 1, Ceil((V.Position.Y + Extent) * 0.5));
    CS := Cos(V.Angle); SN := Sin(V.Angle);
    for Y := Y0 to Y1 do
      for X := X0 to X1 do
      begin
        DX := X * 2 + 1 - V.Position.X; DY := Y * 2 + 1 - V.Position.Y;
        Q := Sqr((DX * CS + DY * SN) / RX) + Sqr((-DX * SN + DY * CS) / RY);
        if Q >= 1 then Continue;
        W := Sqr(1 - Q) * 2.0 * V.Opacity;
        C := FFluidField[Y * FW + X];
        C.Density := C.Density + W;
        C.R := C.R + ((V.Color shr 16) and 255) * W;
        C.G := C.G + ((V.Color shr 8) and 255) * W;
        C.B := C.B + (V.Color and 255) * W;
        FFluidField[Y * FW + X] := C;
      end;
  end;
  for Y := 0 to FHeight - 1 do
    for X := 0 to FWidth - 1 do
    begin
      FX := Max(0.0, (X - 0.5) * 0.5); FY := Max(0.0, (Y - 0.5) * 0.5);
      IX := Min(FW - 1, Floor(FX)); IY := Min(FH - 1, Floor(FY));
      PX := Min(FW - 1, IX + 1); PY := Min(FH - 1, IY + 1);
      TX := FX - IX; TY := FY - IY;
      C00 := FFluidField[IY * FW + IX]; C10 := FFluidField[IY * FW + PX];
      C01 := FFluidField[PY * FW + IX]; C11 := FFluidField[PY * FW + PX];
      Density := Mix(C00.Density, C10.Density, C01.Density, C11.Density);
      if Density <= 0.25 then Continue;
      Cover := EnsureRange((Density - 0.25) / 0.35, 0.0, 1.0);
      Cover := Cover * Cover * (3 - 2 * Cover);
      // Interpolate the density gradient; light the surface from the upper left.
      // Keep the silhouette and opacity independent of the lighting.
      NX := ((C10.Density - C00.Density) * (1 - TY) +
        (C11.Density - C01.Density) * TY) * 0.55;
      NY := ((C01.Density - C00.Density) * (1 - TX) +
        (C11.Density - C10.Density) * TX) * 0.55;
      W := 1 / Sqrt(1 + Sqr(NX) + Sqr(NY));
      Light := EnsureRange(0.92 + (W * (0.8 + 0.36 * NX + 0.48 * NY) - 0.8) * 0.65,
        0.64, 1.12);
      Shine := 28 * Sqr(EnsureRange((Light - 0.94) / 0.11, 0.0, 1.0));
      Red := Min(255.0, Mix(C00.R, C10.R, C01.R, C11.R) / Density * Light + Shine);
      Green := Min(255.0, Mix(C00.G, C10.G, C01.G, C11.G) / Density * Light + Shine);
      Blue := Min(255.0, Mix(C00.B, C10.B, C01.B, C11.B) / Density * Light + Shine);
      A := EnsureRange(Round(Cover * S.Opacity * 255), 0, 255);
      I := (Y * FWidth + X) * 4;
      FOverlay[I] := Round(Blue * A / 255); FOverlay[I + 1] := Round(Green * A / 255);
      FOverlay[I + 2] := Round(Red * A / 255); FOverlay[I + 3] := A;
    end;
end;

procedure TFXRenderer.Render(const Input: TFXPixels; Width, Height: Integer;
  Time: Double; const Settings: TFXSettings; out Output: TFXPixels);
var
  I, SourceHeight: Integer;
  RenderInput: TFXPixels;
  ComResult, DrawResult: HRESULT;
  PhaseTimer: TStopwatch;
begin
  if (Width <= 0) or (Height <= 0) or (Width > 8192) or (Height > 8192) or
    (Int64(Width) * Height > FX_MAX_PIXELS) or
    (Length(Input) <> Width * Height) then
    raise EArgumentException.Create('パーティクル演出の画像サイズが不正です。');
  SourceHeight := Height;
  Height := Height + EnsureRange(Settings.BottomMargin, 0, Min(8192 - Height, FX_MAX_PIXELS div Width - Height));
  RenderInput := Input;
  if Height <> SourceHeight then
  begin
    SetLength(FExpandedInput, Width * Height);
    Move(Input[0], FExpandedInput[0], Length(Input) * SizeOf(TFXPixelRGBA));
    FillChar(FExpandedInput[Length(Input)], (Length(FExpandedInput) - Length(Input)) * SizeOf(TFXPixelRGBA), 0);
    RenderInput := FExpandedInput;
  end;
  if IsNan(Time) or IsInfinite(Time) then Time := 0;
  Time := EnsureRange(Time, -1000000.0, 1000000.0);
  ComResult := CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    PhaseTimer := TStopwatch.StartNew;
    FEnvironment.Prepare(RenderInput, Width, Height, Settings, Time + Settings.Offset, SourceHeight);
    FStats.MaskMS := PhaseTimer.ElapsedTicks * 1000 / TStopwatch.Frequency;
    PhaseTimer := TStopwatch.StartNew;
    try
      EnsureResources(Width, Height);
      UpdateSoftColor(Settings.Color);
    except
      ResetGraphics;
      raise;
    end;
    FStats.ResourceMS := PhaseTimer.ElapsedTicks * 1000 / TStopwatch.Frequency;
    PhaseTimer := TStopwatch.StartNew;
    if Settings.Style = fsSlime then
    begin
      if FViscous = nil then FViscous := TFXViscousFlow.Create(FSimulator);
      FViscous.Generate(Time, Settings, FEnvironment, FVisuals);
    end else FSimulator.Generate(Time, Settings, FEnvironment, FVisuals);
    FStats.SimulationMS := PhaseTimer.ElapsedTicks * 1000 / TStopwatch.Frequency;
    PhaseTimer := TStopwatch.StartNew;
    FTarget.BeginDraw;
    try
      FTarget.SetTransform(TD2D1Matrix3x2F.Identity);
      FTarget.Clear(D2D1ColorF(0, 0, 0, 0));
      if Settings.Style <> fsSlime then
      begin
        DrawAccumulation(Settings);
        for I := 0 to FVisuals.Count - 1 do
          if (Settings.DrawMode <> 2) or FVisuals[I].IsSplash then DrawVisual(FVisuals[I], Settings);
      end;
    finally
      DrawResult := FTarget.EndDraw;
    end;
    if Failed(DrawResult) then begin ResetTarget; OleCheck(DrawResult); end;
    FStats.DrawingMS := PhaseTimer.ElapsedTicks * 1000 / TStopwatch.Frequency;
    PhaseTimer := TStopwatch.StartNew;
    OleCheck(FBitmap.CopyPixels(nil, Width * 4, Length(FOverlay), @FOverlay[0]));
    if Settings.Style = fsSlime then DrawViscousField(Settings);
    Composite(RenderInput, Output, Settings.DrawMode = 1);
    FOutputWidth := Width; FOutputHeight := Height;
    FStats.CompositeMS := PhaseTimer.ElapsedTicks * 1000 / TStopwatch.Frequency;
    FStats.VisibleParticles := FVisuals.Count; FStats.Contacts := FSimulator.CollisionCount;
    FStats.SimulatedSteps := FSimulator.SimulatedSteps; FStats.Surfaces := FEnvironment.SurfaceCount;
    if Settings.Style = fsSlime then
    begin
      FStats.Contacts := FViscous.Contacts; FStats.SimulatedSteps := FViscous.SimulatedSteps;
    end;
    FStats.ContourRevision := FEnvironment.Revision;
  finally
    // MTAは所有cookieで生存させる。外部STAで作成した資源はその呼出内で解放する。
    if ComResult = RPC_E_CHANGED_MODE then ResetGraphics;
    if Succeeded(ComResult) then CoUninitialize;
  end;
end;

end.
