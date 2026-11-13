program ParticleFX_Experiment;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// SDKやプラグインDLLを使わず、独立した描画処理で透過素材・演出を検証する。

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, System.IOUtils, System.Diagnostics, System.Classes,
  Winapi.Windows, Winapi.ActiveX, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.GIFImg,
  ParticleFX_Types in '..\Source\Common\ParticleFX_Types.pas',
  ParticleFX_Collision in '..\Source\Common\ParticleFX_Collision.pas',
  ParticleFX_Simulation in '..\Source\Common\ParticleFX_Simulation.pas',
  ParticleFX_Renderer in '..\Source\Common\ParticleFX_Renderer.pas';

const
  WIDTH = 960;
  HEIGHT = 540;

type
  TBytesRow = array[0..MaxInt div 4 - 1] of Byte;
  PBytesRow = ^TBytesRow;

var
  OutputDir: string;
  Source, Empty, Output, FirstResult, SecondResult, SourceCopy: TFXPixels;
  Renderer, ColdRenderer: TFXRenderer;
  Settings: TFXSettings;
  Checks, Failures: Integer;
  Report: TStringBuilder;

procedure Check(Condition: Boolean; const Description: string);
var
  Status: string;
begin
  Inc(Checks);
  if Condition then Status := 'PASS'
  else begin Inc(Failures); Status := 'FAIL'; end;
  Writeln(Status, ' ', Description);
  Report.AppendLine(Status + ' ' + Description);
end;

function EqualPixels(const A, B: TFXPixels): Boolean;
begin
  Result := Length(A) = Length(B);
  if Result and (Length(A) > 0) then Result := CompareMem(@A[0], @B[0], Length(A) * 4);
end;

function CountAlpha(const Pixels: TFXPixels): Integer;
var
  P: TFXPixelRGBA;
begin
  Result := 0;
  for P in Pixels do if P.A > 0 then Inc(Result);
end;

procedure SavePNG(const Name: string; const Pixels: TFXPixels; W, H: Integer);
var
  PNG: TPngImage;
  Row: PBytesRow;
  Alpha: PByteArray;
  X, Y, I: Integer;
begin
  PNG := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, W, H);
  try
    for Y := 0 to H - 1 do
    begin
      Row := PNG.Scanline[Y];
      Alpha := PNG.AlphaScanline[Y];
      for X := 0 to W - 1 do
      begin
        I := Y * W + X;
        Row[X * 3] := Pixels[I].B; Row[X * 3 + 1] := Pixels[I].G;
        Row[X * 3 + 2] := Pixels[I].R;
        Alpha[X] := Pixels[I].A;
      end;
    end;
    PNG.SaveToFile(TPath.Combine(OutputDir, Name + '.png'));
  finally
    PNG.Free;
  end;
end;

function LoadPNG(const Name: string): TFXPixels;
var
  PNG: TPngImage;
  Row: PBytesRow;
  Alpha: PByteArray;
  X, Y, I: Integer;
begin
  PNG := TPngImage.Create;
  try
    PNG.LoadFromFile(TPath.Combine(OutputDir, Name + '.png'));
    SetLength(Result, PNG.Width * PNG.Height);
    for Y := 0 to PNG.Height - 1 do
    begin
      Row := PNG.Scanline[Y]; Alpha := PNG.AlphaScanline[Y];
      for X := 0 to PNG.Width - 1 do
      begin
        I := Y * PNG.Width + X;
        Result[I].B := Row[X * 3]; Result[I].G := Row[X * 3 + 1]; Result[I].R := Row[X * 3 + 2];
        if Alpha <> nil then Result[I].A := Alpha[X] else Result[I].A := 255;
      end;
    end;
  finally
    PNG.Free;
  end;
end;

procedure PaintPixel(var Pixel: TFXPixelRGBA; Color: Cardinal; Coverage: Double);
var
  A, OldA, NewA: Double;
begin
  A := EnsureRange(Coverage, 0.0, 1.0); OldA := Pixel.A / 255;
  NewA := A + OldA * (1 - A);
  if NewA <= 0 then Exit;
  Pixel.R := EnsureRange(Round((((Color shr 16) and 255) * A + Pixel.R * OldA * (1 - A)) / NewA), 0, 255);
  Pixel.G := EnsureRange(Round((((Color shr 8) and 255) * A + Pixel.G * OldA * (1 - A)) / NewA), 0, 255);
  Pixel.B := EnsureRange(Round(((Color and 255) * A + Pixel.B * OldA * (1 - A)) / NewA), 0, 255);
  Pixel.A := Round(NewA * 255);
end;

procedure CollisionChecks;
var
  Environment: TFXEnvironment;
  Input: TFXPixels;
  S: TFXSettings;
  X, Y, I, Revision, Coatings: Integer;
  Hit, Normal: TFXVec;
  Fraction: Double;
  Surface: TFXSurface;
  ValidNormals: Boolean;
  LocalRenderer: TFXRenderer;
  Rendered: TFXPixels;
begin
  Environment := TFXEnvironment.Create;
  try
    SetLength(Input, 64 * 64);
    for Y := 20 to 43 do
      for X := 20 to 43 do Input[Y * 64 + X].A := 255;
    S := FXDefaultSettings(fsSnow); S.Accumulation := False;
    Environment.Prepare(Input, 64, 64, S, 1);
    Check(Environment.Trace(FXVec(0, 32), FXVec(63, 32), 1, Hit, Normal, Fraction) and
      (Hit.X < 20) and (Normal.X < -0.8), 'left-to-right collision returns left surface normal');
    Check(Environment.Trace(FXVec(63, 32), FXVec(0, 32), 1, Hit, Normal, Fraction) and
      (Hit.X > 43) and (Normal.X > 0.8), 'right-to-left collision returns right surface normal');
    Check(Environment.Trace(FXVec(32, 0), FXVec(32, 63), 1, Hit, Normal, Fraction) and
      (Hit.Y < 20) and (Normal.Y < -0.8), 'downward collision returns upper surface normal');
    Check(Environment.Trace(FXVec(32, 63), FXVec(32, 0), 1, Hit, Normal, Fraction) and
      (Hit.Y > 43) and (Normal.Y > 0.8), 'upward collision returns underside normal');
    Revision := Environment.Revision;
    Environment.Prepare(Input, 64, 64, S, 1);
    Check(Environment.Revision = Revision, 'unchanged alpha reuses contour cache');
    FillChar(Input[0], Length(Input) * 4, 0);
    for Y := 0 to 63 do Input[Y * 64 + 30].A := 255;
    Environment.Prepare(Input, 64, 64, S, 1);
    Check(Environment.Revision > Revision, 'changed alpha invalidates contour cache');
    Check(Environment.Trace(FXVec(-400, 32), FXVec(400, 32), 0.5, Hit, Normal, Fraction),
      'fast particle cannot tunnel through a one-pixel wall');
    FillChar(Input[0], Length(Input) * 4, 0);
    for Y := 20 to 43 do
      for X := 20 to 43 do Input[Y * 64 + X].A := 64;
    Environment.Prepare(Input, 64, 64, S, 1);
    Check(not Environment.Trace(FXVec(0, 32), FXVec(63, 32), 1, Hit, Normal, Fraction),
      'alpha 64 is excluded at threshold 128');
    for Y := 20 to 43 do
      for X := 20 to 43 do Input[Y * 64 + X].A := 192;
    Environment.Prepare(Input, 64, 64, S, 1);
    Check(Environment.Trace(FXVec(0, 32), FXVec(63, 32), 1, Hit, Normal, Fraction),
      'alpha 192 is included at threshold 128');
    S.Accumulation := True; S.AccumAmount := 100; S.MaxThickness := 8;
    Environment.Prepare(Input, 64, 64, S, 1);
    ValidNormals := False;
    for I := 0 to Environment.SurfaceCount - 1 do
    begin
      Surface := Environment.Surfaces[I];
      if not Surface.Valid or Surface.IsCoating then Continue;
      ValidNormals := True;
      if Surface.Normal.Y > -0.5 then begin ValidNormals := False; Break; end;
    end;
    Check(ValidNormals, 'downward gravity accumulates on upper-facing surfaces');
    S.GravityAngle := 90;
    Environment.Prepare(Input, 64, 64, S, 1);
    ValidNormals := False;
    for I := 0 to Environment.SurfaceCount - 1 do
    begin
      Surface := Environment.Surfaces[I];
      if not Surface.Valid or Surface.IsCoating then Continue;
      ValidNormals := True;
      if Surface.Normal.X > -0.5 then begin ValidNormals := False; Break; end;
    end;
    Check(ValidNormals, 'rotated gravity accumulates on the corresponding side');
    S.GravityAngle := 0; S.Wind := 200;
    Environment.Prepare(Input, 64, 64, S, 1);
    Coatings := 0;
    for I := 0 to Environment.SurfaceCount - 1 do
    begin
      Surface := Environment.Surfaces[I];
      if Surface.Valid and Surface.IsCoating and (Surface.Normal.X < -0.5) and
        (Surface.Thickness <= 3.5) then Inc(Coatings);
    end;
    Check(Coatings > 0, 'crosswind adds a thin windward coating without thick vertical piles');
    S.AccumAmount := 0;
    Environment.Prepare(Input, 64, 64, S, 1);
    Check(Environment.SurfaceCount = 0, 'accumulation amount zero clears geometry');
    FillChar(Input[0], Length(Input) * 4, 0);
    for Y := 20 to 43 do Input[Y * 64 + 31].A := 255;
    S := FXDefaultSettings(fsSnow); S.Rate := 0; S.MaxThickness := 8; S.AccumAmount := 100;
    LocalRenderer := TFXRenderer.Create;
    try
      LocalRenderer.Render(Input, 64, 64, 1, S, Rendered);
      Check(Rendered[15 * 64 + 31].A > 0, 'one-pixel-wide contours produce visible accumulation');
    finally
      LocalRenderer.Free;
    end;
  finally
    Environment.Free;
  end;
end;

procedure MotionChecks;
var
  Environment: TFXEnvironment;
  Simulator: TFXSimulator;
  Visuals: TFXVisualList;
  Input: TFXPixels;
  S: TFXSettings;
  Direction: TFXVec;
  I, Angle: Integer;
  Valid: Boolean;
begin
  Environment := TFXEnvironment.Create;
  Simulator := TFXSimulator.Create;
  Visuals := TFXVisualList.Create;
  try
    SetLength(Input, 128 * 128);
    for Angle := 0 to 3 do
    begin
      S := FXDefaultSettings(fsRain); S.Angle := Angle * 90;
      S.Rate := 20; S.Speed := 80; S.SpeedVariation := 0; S.Depth := 0;
      S.DirectionSpread := 0; S.Gravity := 0; S.Sway := 0;
      Environment.Prepare(Input, 128, 128, S, 1);
      Simulator.Generate(2, S, Environment, Visuals);
      Direction := FXDirection(S.Angle); Valid := Visuals.Count > 0;
      for I := 0 to Visuals.Count - 1 do
        if FXDot(Visuals[I].Velocity, Direction) < 79.9 then Valid := False;
      Check(Valid, Format('automatic upstream emission and travel at %d degrees', [Angle * 90]));
    end;
    S := FXDefaultSettings(fsWater); S.Emission := feShot;
    S.AutomaticEmitter := False;
    S.Speed := 20; S.Gravity := 80; S.Angle := 90; S.DirectionSpread := 0;
    S.Depth := 0; S.SpeedVariation := 0; S.Burst := 4;
    Environment.Prepare(Input, 128, 128, S, 1);
    Simulator.Generate(0.5, S, Environment, Visuals);
    Valid := Visuals.Count = 4;
    for I := 0 to Visuals.Count - 1 do
      if (Visuals[I].Velocity.X < 19.9) or (Visuals[I].Velocity.Y < 39) then Valid := False;
    Check(Valid, 'horizontal shot and downward gravity act independently');
    S.Gravity := 0;
    Environment.Prepare(Input, 128, 128, S, 1);
    Simulator.Generate(0.5, S, Environment, Visuals);
    Valid := Visuals.Count = 4;
    for I := 0 to Visuals.Count - 1 do
      if Abs(Visuals[I].Velocity.Y) > 0.001 then Valid := False;
    Check(Valid, 'zero gravity produces straight motion');
    S.Speed := 10000; S.MaxSpeed := 50;
    Environment.Prepare(Input, 128, 128, S, 1);
    Simulator.Generate(0.1, S, Environment, Visuals);
    Valid := Visuals.Count = 4;
    for I := 0 to Visuals.Count - 1 do
      if FXLength(Visuals[I].Velocity) > 50.001 then Valid := False;
    Check(Valid, 'maximum velocity is enforced');
    S := FXDefaultSettings(fsFountain); S.Speed := 20; S.Gravity := 0;
    S.Duration := 1; S.Period := 3; S.Lifetime := 0.5;
    Environment.Prepare(Input, 128, 128, S, 1);
    Simulator.Generate(0.6, S, Environment, Visuals);
    Check(Visuals.Count > 0, 'intermittent jet is active during the first emission');
    Simulator.Generate(2.8, S, Environment, Visuals);
    Check(Visuals.Count = 0, 'intermittent jet stops between emissions');
    Simulator.Generate(3.3, S, Environment, Visuals);
    Check(Visuals.Count > 0, 'intermittent jet restarts at its period');
  finally
    Visuals.Free; Simulator.Free; Environment.Free;
  end;
end;

procedure AlphaAndCacheChecks;
var
  S: TFXSettings;
  TransparentResult, CompositeResult, SemiTransparent: TFXPixels;
  I, Best, A, OA, ExpectedR, ExpectedG, ExpectedB, Pass: Integer;
  ThreadError: string;
  Worker: TThread;
  Timer: TStopwatch;
begin
  S := FXDefaultSettings(fsSand); S.Emission := feShot; S.Shape := shGrain;
  S.AutomaticEmitter := False;
  S.Burst := 1; S.Speed := 0; S.Gravity := 0; S.Sway := 0;
  S.Size := 14; S.SizeVariation := 0; S.Depth := 0; S.Opacity := 0.5;
  S.CustomColor := True; S.Color := $8040C0; S.Collision := False; S.Accumulation := False;
  S.ColorVariation := 0;
  Renderer.Render(Empty, WIDTH, HEIGHT, 0.5, S, TransparentResult);
  Best := 0;
  for I := 1 to High(TransparentResult) do
    if TransparentResult[I].A > TransparentResult[Best].A then Best := I;
  A := TransparentResult[Best].A;
  Check((A >= 126) and (A <= 129) and (Abs(TransparentResult[Best].R - 128) <= 2) and
    (Abs(TransparentResult[Best].G - 64) <= 2) and (Abs(TransparentResult[Best].B - 192) <= 2),
    'PBGRA readback returns straight-alpha RGBA without dark fringes');
  SetLength(SemiTransparent, WIDTH * HEIGHT);
  for I := 0 to High(SemiTransparent) do
  begin
    SemiTransparent[I].R := 10; SemiTransparent[I].G := 50;
    SemiTransparent[I].B := 90; SemiTransparent[I].A := 80;
  end;
  Renderer.Render(SemiTransparent, WIDTH, HEIGHT, 0.5, S, CompositeResult);
  OA := A + Round(80 * (255 - A) / 255);
  ExpectedR := Round((TransparentResult[Best].R * A + 10 * 80 * (255 - A) / 255) / OA);
  ExpectedG := Round((TransparentResult[Best].G * A + 50 * 80 * (255 - A) / 255) / OA);
  ExpectedB := Round((TransparentResult[Best].B * A + 90 * 80 * (255 - A) / 255) / OA);
  Check((Abs(CompositeResult[Best].A - OA) <= 1) and
    (Abs(CompositeResult[Best].R - ExpectedR) <= 2) and
    (Abs(CompositeResult[Best].G - ExpectedG) <= 2) and
    (Abs(CompositeResult[Best].B - ExpectedB) <= 2), 'source-over blending preserves semitransparent image colors');

  S := FXDefaultSettings(fsSnow); S.Wind := 70; S.Gust := 40;
  S.Turbulence := 20; S.Vortex := 30;
  Renderer.Render(Source, WIDTH, HEIGHT, 2.345, S, FirstResult);
  Renderer.Render(Source, WIDTH, HEIGHT, 7.125, S, Output);
  Renderer.Render(Source, WIDTH, HEIGHT, 2.345, S, SecondResult);
  Check(EqualPixels(FirstResult, SecondResult), 'gust, turbulence and vortex reproduce after reverse seek');
  ColdRenderer.Render(Source, WIDTH, HEIGHT, 2.345, S, SecondResult);
  Check(EqualPixels(FirstResult, SecondResult), 'dynamic winds reproduce with an empty cache');
  Timer := TStopwatch.StartNew;
  Renderer.Render(Source, WIDTH, HEIGHT, 2.345 + 1 / 30, S, Output);
  Writeln(Format('PERF warm frame: %dms steps=%d', [Timer.ElapsedMilliseconds, Renderer.Stats.SimulatedSteps]));
  Check(Renderer.Stats.SimulatedSteps < 20000, 'adjacent frame reuses fixed-step particle states');

  ThreadError := '';
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      LocalRenderer: TFXRenderer;
      Pixels: TFXPixels;
    begin
      LocalRenderer := TFXRenderer.Create;
      try
        try
          LocalRenderer.Render(Source, WIDTH, HEIGHT, 1, S, Pixels);
          LocalRenderer.Render(Source, WIDTH, HEIGHT, 2, S, Pixels);
        except
          on E: Exception do ThreadError := E.ClassName + ': ' + E.Message;
        end;
      finally
        LocalRenderer.Free;
      end;
    end);
  Worker.FreeOnTerminate := False;
  Worker.Start; Worker.WaitFor; Worker.Free;
  Check(ThreadError = '', 'renderer safely initializes and releases COM on a fresh worker thread');
  if ThreadError <> '' then Writeln(ThreadError);

  // ホストがフレーム間でCOMを終了する状況も、MTA cookieで資源を維持する。
  ThreadError := '';
  CoUninitialize;
  try
    for Pass := 0 to 1 do
    begin
      Worker := TThread.CreateAnonymousThread(
        procedure
        var
          Pixels: TFXPixels;
        begin
          CoInitializeEx(nil, COINIT_MULTITHREADED);
          try
            try
              Renderer.Render(Source, WIDTH, HEIGHT, 2.345, S, Pixels);
              if not EqualPixels(FirstResult, Pixels) then ThreadError := 'Different pixels across apartments';
            except
              on E: Exception do ThreadError := E.ClassName + ': ' + E.Message;
            end;
          finally
            CoUninitialize;
          end;
        end);
      Worker.FreeOnTerminate := False;
      Worker.Start; Worker.WaitFor; Worker.Free;
    end;
  finally
    CoInitializeEx(nil, COINIT_MULTITHREADED);
  end;
  Check(ThreadError = '', 'graphics survive host apartment teardown and sequential worker threads');
  if ThreadError <> '' then Writeln(ThreadError);
end;

procedure MakeFixture(out Pixels: TFXPixels);
var
  X, Y: Integer;
  PX, PY, D, RX, RY: Double;
  Pixel: TFXPixelRGBA;
  function Circle(CX, CY, Radius: Double): Double;
  begin
    Result := 0.5 - (Sqrt(Sqr(PX - CX) + Sqr(PY - CY)) - Radius);
  end;
  function RoundedRect(L, T, R, B, Radius: Double): Double;
  var
    QX, QY: Double;
  begin
    QX := Abs(PX - (L + R) * 0.5) - (R - L) * 0.5 + Radius;
    QY := Abs(PY - (T + B) * 0.5) - (B - T) * 0.5 + Radius;
    Result := 0.5 - (Sqrt(Sqr(Max(QX, 0.0)) + Sqr(Max(QY, 0.0))) + Min(Max(QX, QY), 0.0) - Radius);
  end;
begin
  SetLength(Pixels, WIDTH * HEIGHT);
  for Y := 0 to HEIGHT - 1 do
    for X := 0 to WIDTH - 1 do
    begin
      Pixel := Default(TFXPixelRGBA); PX := X + 0.5; PY := Y + 0.5;
      // 頭・首・丸い肩・胴体。上面、斜面、側面、下面を1枚に含める。
      PaintPixel(Pixel, $DCA77E, RoundedRect(451, 203, 509, 287, 22));
      PaintPixel(Pixel, $438991, RoundedRect(331, 254, 629, 486, 76));
      PaintPixel(Pixel, $EEC5A3, Circle(480, 163, 61));
      if PY < 149 + Sin((PX - 428) * 0.04) * 13 then
        PaintPixel(Pixel, $3A485C, Circle(480, 157, 65));
      PaintPixel(Pixel, $30465E, Circle(459, 168, 3.8));
      PaintPixel(Pixel, $30465E, Circle(501, 168, 3.8));
      // 左の段差と穴。下に空間のある上面を持つ。
      PaintPixel(Pixel, $B07D57, RoundedRect(54, 303, 272, 332, 4));
      PaintPixel(Pixel, $816955, RoundedRect(78, 330, 101, 463, 2));
      PaintPixel(Pixel, $816955, RoundedRect(227, 330, 250, 463, 2));
      D := Sqrt(Sqr(PX - 181) + Sqr(PY - 226));
      PaintPixel(Pixel, $96A8BB, Min(40.5 - D, D - 24.5));
      // 右の斜面。水平面への積雪と区別できるよう傾斜を付ける。
      RX := (PX - 754) * Cos(-0.42) + (PY - 307) * Sin(-0.42);
      RY := -(PX - 754) * Sin(-0.42) + (PY - 307) * Cos(-0.42);
      D := Min(115 - Abs(RX), 13 - Abs(RY));
      PaintPixel(Pixel, $72879B, D + 0.5);
      // しきい値検証用の半透明面(左64、右192)。
      PaintPixel(Pixel, $C49BC5, EnsureRange(RoundedRect(691, 405, 759, 465, 8), 0.0, 1.0) * 64 / 255);
      PaintPixel(Pixel, $C49BC5, EnsureRange(RoundedRect(781, 405, 849, 465, 8), 0.0, 1.0) * 192 / 255);
      Pixels[Y * WIDTH + X] := Pixel;
    end;
end;

procedure RenderExample(const Name: string; Time: Double; const Input: TFXPixels);
var
  Timer: TStopwatch;
begin
  Timer := TStopwatch.StartNew;
  Renderer.Render(Input, WIDTH, HEIGHT, Time, Settings, Output);
  Writeln(Format('RENDER %s %dms particles=%d contacts=%d steps=%d',
    [Name, Timer.ElapsedMilliseconds, Renderer.Stats.VisibleParticles,
     Renderer.Stats.Contacts, Renderer.Stats.SimulatedSteps]));
  SavePNG(Name, Output, WIDTH, HEIGHT);
  Check(Length(Output) = WIDTH * HEIGHT, Name + ': valid RGBA dimensions');
end;

procedure FullHDChecks;
var
  Input, Pixels: TFXPixels;
  S: TFXSettings;
  LocalRenderer: TFXRenderer;
  X, Y, I, BottomPixels: Integer;
  Timer: TStopwatch;
  FirstMS, WarmMS: Int64;
begin
  SetLength(Input, 1920 * 1080);
  LocalRenderer := TFXRenderer.Create;
  try
    S := FXDefaultSettings(fsSnow);
    LocalRenderer.Render(Input, 1920, 1080, 0, S, Pixels);
    BottomPixels := 0;
    for Y := 980 to 1079 do
      for X := 0 to 1919 do
        if Pixels[Y * 1920 + X].A > 0 then Inc(BottomPixels);
    Check(BottomPixels > 100, 'automatic prewarm fills the bottom of a Full HD snow frame at time zero');
    for Y := 0 to 1079 do
      for X := 0 to 1919 do Input[Y * 1920 + X] := Source[(Y div 2) * WIDTH + X div 2];
    Timer := TStopwatch.StartNew;
    LocalRenderer.Render(Input, 1920, 1080, 2, S, Pixels);
    FirstMS := Timer.ElapsedMilliseconds;
    Timer := TStopwatch.StartNew;
    for I := 1 to 24 do LocalRenderer.Render(Input, 1920, 1080, 2 + I / 30, S, Pixels);
    WarmMS := Timer.ElapsedMilliseconds;
    Writeln(Format('PERF 1920x1080 snow: cold=%dms warm-average=%.2fms (24 frames)',
      [FirstMS, WarmMS / 24]));
    Report.AppendLine(Format('PERF Full HD snow cold=%dms warm-average=%.2fms', [FirstMS, WarmMS / 24]));
    Writeln(Format('PERF phases mask=%.2f resources=%.2f physics=%.2f draw=%.2f composite=%.2f ms rev=%d steps=%d',
      [LocalRenderer.Stats.MaskMS, LocalRenderer.Stats.ResourceMS, LocalRenderer.Stats.SimulationMS,
       LocalRenderer.Stats.DrawingMS, LocalRenderer.Stats.CompositeMS,
       LocalRenderer.Stats.ContourRevision, LocalRenderer.Stats.SimulatedSteps]));
    Check((Length(Pixels) = 1920 * 1080) and (LocalRenderer.Stats.VisibleParticles > 0),
      'Full HD consecutive-frame rendering completes with visible particles');
  finally
    LocalRenderer.Free;
  end;
end;

procedure PresetChecks;
var
  Environment: TFXEnvironment;
  Simulator: TFXSimulator;
  Visuals: TFXVisualList;
  S: TFXSettings;
  Preset, I: Integer;
  Valid: Boolean;
begin
  Environment := TFXEnvironment.Create;
  Simulator := TFXSimulator.Create;
  Visuals := TFXVisualList.Create;
  try
    for Preset := 0 to 19 do
    begin
      S := FXPresetSettings(fsSnow, Preset);
      Environment.Prepare(Empty, WIDTH, HEIGHT, S, 0.5);
      Simulator.Generate(0.5, S, Environment, Visuals);
      Valid := (Visuals.Count > 0) and (Visuals.Count <= FX_MAX_PARTICLES * 6);
      for I := 0 to Visuals.Count - 1 do
        Valid := Valid and not IsNan(Visuals[I].Position.X) and not IsInfinite(Visuals[I].Position.Y) and
          (Visuals[I].Opacity >= 0) and (Visuals[I].Opacity <= 1) and (Visuals[I].Size > 0);
      Check(Valid, Format('preset %d simulates visible, finite and bounded particles without a host', [Preset]));
    end;
  finally
    Visuals.Free; Simulator.Free; Environment.Free;
  end;
end;

procedure CreateMotionPreview;
const
  Frames = 32;
  TileWidth = WIDTH div 2;
  TileHeight = HEIGHT div 2;
  Header = 28;
  Names: array[0..3] of string = ('RAIN / alpha collisions', 'SNOW / accumulation 0-100',
    'WATER / shot + splash', 'FOUNTAIN / continuous jet');
var
  Renderers: array[0..3] of TFXRenderer;
  S: TFXSettings;
  Pixels: TFXPixels;
  GIF, DecodedGIF: TGIFImage;
  Frame: TGIFFrame;
  Control: TGIFGraphicControlExtension;
  Loop: TGIFAppExtNSLoop;
  Bitmap: TBitmap;
  Row: PBytesRow;
  F, Tile, X, Y, I, A, BG, OX, OY: Integer;
  SampleColor: TColor;
  ColorsValid: Boolean;
  Time: Double;
begin
  GIF := TGIFImage.Create;
  Bitmap := TBitmap.Create;
  for Tile := 0 to 3 do Renderers[Tile] := TFXRenderer.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(TileWidth * 2, (TileHeight + Header) * 2);
    GIF.ColorReduction := rmQuantize;
    GIF.DitherMode := dmNearest;
    for F := 0 to Frames - 1 do
    begin
      // GIFの減色器が入力Bitmapを24bitへ変換するため、書込前に毎回32bitへ戻す。
      Bitmap.PixelFormat := pf32bit;
      Time := F * 0.08;
      Bitmap.Canvas.Brush.Color := RGB(16, 27, 43);
      Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
      Bitmap.Canvas.Font.Name := 'Consolas'; Bitmap.Canvas.Font.Size := 11;
      Bitmap.Canvas.Font.Color := RGB(223, 237, 245);
      for Tile := 0 to 3 do
      begin
        case Tile of
          0: S := FXDefaultSettings(fsRain);
          1: begin S := FXDefaultSettings(fsSnow); S.AccumAmount := F / (Frames - 1) * 100; end;
          2: begin S := FXDefaultSettings(fsWater); S.AutomaticEmitter := False;
            S.EmitterX := -420; S.EmitterY := -120; end;
          3: begin S := FXDefaultSettings(fsFountain); S.AutomaticEmitter := False;
            S.EmitterY := 200; S.FloorEnabled := True; end;
        end;
        if Tile = 3 then Renderers[Tile].Render(Empty, WIDTH, HEIGHT, Time, S, Pixels)
        else if Tile = 2 then Renderers[Tile].Render(Source, WIDTH, HEIGHT, Time, S, Pixels)
        else Renderers[Tile].Render(Source, WIDTH, HEIGHT, Time + 2, S, Pixels);
        OX := (Tile mod 2) * TileWidth;
        OY := (Tile div 2) * (TileHeight + Header);
        Bitmap.Canvas.TextOut(OX + 8, OY + 6, Names[Tile]);
        for Y := 0 to TileHeight - 1 do
        begin
          Row := Bitmap.ScanLine[OY + Header + Y];
          for X := 0 to TileWidth - 1 do
          begin
            I := (Y * 2) * WIDTH + X * 2;
            if ((X div 12 + Y div 12) mod 2) = 0 then BG := 33 else BG := 43;
            A := Pixels[I].A;
            Row[(OX + X) * 4] := (Pixels[I].B * A + (BG + 20) * (255 - A)) div 255;
            Row[(OX + X) * 4 + 1] := (Pixels[I].G * A + (BG + 9) * (255 - A)) div 255;
            Row[(OX + X) * 4 + 2] := (Pixels[I].R * A + BG * (255 - A)) div 255;
            Row[(OX + X) * 4 + 3] := 255;
          end;
        end;
      end;
      Frame := GIF.Add(Bitmap);
      Control := TGIFGraphicControlExtension.Create(Frame); Control.Delay := 8;
      Writeln(Format('ANIMATION %d/%d', [F + 1, Frames]));
    end;
    Loop := TGIFAppExtNSLoop.Create(GIF.Images[0]); Loop.Loops := 0;
    GIF.SaveToFile(TPath.Combine(OutputDir, 'motion_demo.gif'));
    Check(GIF.Images.Count = Frames, 'animated preview contains all 32 independently rendered frames');
    DecodedGIF := TGIFImage.Create;
    try
      DecodedGIF.LoadFromFile(TPath.Combine(OutputDir, 'motion_demo.gif'));
      ColorsValid := DecodedGIF.Images.Count = Frames;
      for F := 0 to DecodedGIF.Images.Count - 1 do
      begin
        SampleColor := DecodedGIF.Images[F].Bitmap.Canvas.Pixels[TileWidth div 2, Header + 200];
        ColorsValid := ColorsValid and (Abs(Integer(GetRValue(SampleColor)) - $43) < 16) and
          (Abs(Integer(GetGValue(SampleColor)) - $89) < 16) and
          (Abs(Integer(GetBValue(SampleColor)) - $91) < 16);
      end;
      Check(ColorsValid, 'all encoded GIF frames preserve the original image colors and geometry');
    finally
      DecodedGIF.Free;
    end;
  finally
    for Tile := 0 to 3 do Renderers[Tile].Free;
    Bitmap.Free; GIF.Free;
  end;
end;

procedure Run;
var
  Area0, Area50, Area100: Integer;
  Style: TFXStyle;
  DefaultsVisible: Boolean;
begin
  OutputDir := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), 'Preview'));
  if ParamCount > 0 then OutputDir := TPath.GetFullPath(ParamStr(1));
  ForceDirectories(OutputDir);
  MakeFixture(Source); SourceCopy := Copy(Source);
  SetLength(Empty, WIDTH * HEIGHT);
  SavePNG('00_source', Source, WIDTH, HEIGHT);
  Output := LoadPNG('00_source');
  Check(EqualPixels(Source, Output), 'sample PNG roundtrip preserves orientation, color and alpha');

  Settings := FXDefaultSettings(fsRain);
  RenderExample('01_rain', 2, Source);
  Settings := FXDefaultSettings(fsSnow); Settings.AccumAmount := 0;
  RenderExample('02_snow_000', 4, Source);
  Settings.AccumAmount := 50;
  RenderExample('03_snow_050', 4, Source);
  Settings.AccumAmount := 100;
  RenderExample('04_snow_100', 4, Source);
  FirstResult := Copy(Output);
  Renderer.Render(Source, WIDTH, HEIGHT, 6, Settings, Output);
  Renderer.Render(Source, WIDTH, HEIGHT, 4, Settings, SecondResult);
  Check(EqualPixels(FirstResult, SecondResult), 'reverse seek reproduces identical pixels');
  ColdRenderer.Render(Source, WIDTH, HEIGHT, 4, Settings, SecondResult);
  Check(EqualPixels(FirstResult, SecondResult), 'cold and warm caches reproduce identical pixels');
  Check(EqualPixels(Source, SourceCopy), 'input RGBA is unchanged');

  Settings := FXDefaultSettings(fsRain); Settings.Angle := 90; Settings.Gravity := 0;
  RenderExample('05_sideways_rain', 2, Source);
  Settings := FXDefaultSettings(fsSnow); Settings.Angle := 180; Settings.GravityAngle := 180;
  Settings.AccumAmount := 65;
  RenderExample('06_upward_snow', 4, Source);
  Settings := FXDefaultSettings(fsWater); Settings.AutomaticEmitter := False;
  Settings.EmitterX := -420; Settings.EmitterY := -120;
  RenderExample('07_water_shot', 0.55, Source);
  Settings := FXDefaultSettings(fsFountain); Settings.AutomaticEmitter := False;
  Settings.EmitterY := 200; Settings.FloorEnabled := True;
  RenderExample('08_fountain', 1.6, Empty);
  Settings := FXDefaultSettings(fsPetal); Settings.Wind := 30;
  RenderExample('09_petals', 3, Source);
  Settings := FXDefaultSettings(fsConfetti); Settings.FloorEnabled := True;
  Settings.AccumAmount := 70;
  RenderExample('10_confetti', 3, Empty);
  Settings := FXDefaultSettings(fsSpark);
  RenderExample('11_explosion', 0.6, Empty);
  Settings := FXPresetSettings(fsSand, 19);
  RenderExample('12_sandstorm', 3, Source);
  Settings := FXDefaultSettings(fsHail);
  RenderExample('13_hail', 2, Source);
  Settings := FXDefaultSettings(fsInk); Settings.AutomaticEmitter := False;
  Settings.EmitterX := -420; Settings.EmitterY := -120;
  RenderExample('14_ink', 0.7, Source);
  Settings := FXPresetSettings(fsSnow, 4); Settings.AccumAmount := 65;
  RenderExample('15_blizzard', 3, Source);
  Settings := FXDefaultSettings(fsPetal); Settings.Vortex := 130;
  Settings.Emission := feExplosion; Settings.Gravity := 0; Settings.Speed := 180;
  Settings.DirectionSpread := 120; Settings.Angle := 120;
  RenderExample('16_vortex_fan', 1.4, Empty);
  Settings := FXDefaultSettings(fsWater);
  RenderExample('17_water_default', 0.75, Source);
  Settings := FXDefaultSettings(fsFountain);
  RenderExample('18_fountain_default', 1.5, Empty);
  Settings := FXDefaultSettings(fsSnow); Settings.DrawMode := 2; Settings.AccumAmount := 70;
  RenderExample('19_contact_accumulation_only', 4, Source);

  DefaultsVisible := True;
  for Style := Low(TFXStyle) to High(TFXStyle) do
  begin
    Settings := FXDefaultSettings(Style);
    Renderer.Render(Empty, WIDTH, HEIGHT, 0.7, Settings, Output);
    if CountAlpha(Output) = 0 then
    begin
      DefaultsVisible := False;
      Writeln('EMPTY DEFAULT STYLE ', FXStyleName(Style));
    end;
  end;
  Check(DefaultsVisible, 'all eleven styles produce visible standalone effects without manual emitter positioning');
  Settings := FXDefaultSettings(fsRain); Settings.DrawMode := 2;
  Renderer.Render(Empty, WIDTH, HEIGHT, 2, Settings, Output);
  Check(CountAlpha(Output) = 0, 'contact-only mode suppresses airborne particles for layered compositions');

  Settings := FXDefaultSettings(fsRain); Settings.Rate := 0; Settings.Accumulation := False;
  Renderer.Render(Source, WIDTH, HEIGHT, 2, Settings, Output);
  Check(EqualPixels(Source, Output), 'disabled particles and accumulation preserve all bytes');
  Settings := FXDefaultSettings(fsSnow); Settings.Rate := 0; Settings.AccumAmount := 0;
  Renderer.Render(Source, WIDTH, HEIGHT, 2, Settings, Output);
  Check(EqualPixels(Source, Output), 'accumulation zero leaves no old snow');
  Area0 := CountAlpha(Output);
  Settings.AccumAmount := 50;
  Renderer.Render(Source, WIDTH, HEIGHT, 2, Settings, Output);
  Area50 := CountAlpha(Output);
  Settings.AccumAmount := 100;
  Renderer.Render(Source, WIDTH, HEIGHT, 2, Settings, Output);
  Area100 := CountAlpha(Output);
  Check((Area0 < Area50) and (Area50 < Area100), 'accumulation area grows monotonically from zero through 50 to 100');
  Settings := FXDefaultSettings(fsSpark); Settings.StartTime := 3;
  Renderer.Render(Empty, WIDTH, HEIGHT, 2, Settings, Output);
  Check(CountAlpha(Output) = 0, 'burst is invisible before start');
  Renderer.Render(Empty, WIDTH, HEIGHT, 40, Settings, Output);
  Check(CountAlpha(Output) = 0, 'expired burst leaves transparent background');

  CollisionChecks;
  MotionChecks;
  AlphaAndCacheChecks;
  FullHDChecks;
  PresetChecks;
  if (ParamCount >= 2) and SameText(ParamStr(2), 'animation') then CreateMotionPreview;

  TFile.WriteAllText(TPath.Combine(OutputDir, 'checks.txt'),
    Report.ToString + Format('Checks=%d Failures=%d', [Checks, Failures]), TEncoding.UTF8);
  Writeln(Format('Checks=%d Failures=%d Output=%s', [Checks, Failures, OutputDir]));
end;

begin
  CoInitializeEx(nil, COINIT_MULTITHREADED);
  Report := TStringBuilder.Create;
  Renderer := TFXRenderer.Create;
  ColdRenderer := TFXRenderer.Create;
  try
    try
      Run;
    except
      on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); ExitCode := 1; end;
    end;
    if Failures > 0 then ExitCode := 1;
  finally
    ColdRenderer.Free; Renderer.Free; Report.Free;
    CoUninitialize;
  end;
end.
