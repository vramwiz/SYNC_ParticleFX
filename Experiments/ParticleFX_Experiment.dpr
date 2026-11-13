program ParticleFX_Experiment;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// SDKやプラグインDLLを使わず、独立した描画処理で透過素材・演出を検証する。

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, System.IOUtils, System.Diagnostics, System.Classes,
  System.Generics.Collections,
  Winapi.Windows, Winapi.ActiveX, Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.GIFImg,
  ParticleFX_Types in '..\Source\Common\ParticleFX_Types.pas',
  ParticleFX_Collision in '..\Source\Common\ParticleFX_Collision.pas',
  ParticleFX_Simulation in '..\Source\Common\ParticleFX_Simulation.pas',
  ParticleFX_Viscous in '..\Source\Common\ParticleFX_Viscous.pas',
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
  I, Angle, Quadrant, Directions: Integer;
  Emission: TFXEmission;
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
    // 無重力と全方向はプリセットを使わず、共通の運動・発生設定で組み合わせる。
    for Emission := feExplosion to feJet do
    begin
      S := FXDefaultSettings(fsWater); S.Emission := Emission;
      S.AutomaticEmitter := False; S.EmitterRange := 0; S.Speed := 20;
      S.Gravity := 0; S.Drag := 0; S.Sway := 0; S.DirectionSpread := 360;
      S.Burst := 128; S.Depth := 0; S.SpeedVariation := 0;
      Environment.Prepare(Input, 128, 128, S, 0.5);
      Simulator.Generate(0.5, S, Environment, Visuals);
      Directions := 0; Valid := Visuals.Count > 0;
      for I := 0 to Visuals.Count - 1 do
      begin
        Quadrant := 0;
        if Visuals[I].Velocity.X < 0 then Inc(Quadrant);
        if Visuals[I].Velocity.Y < 0 then Inc(Quadrant, 2);
        Directions := Directions or (1 shl Quadrant);
        Valid := Valid and SameValue(FXLength(Visuals[I].Velocity), 20, 0.001);
      end;
      Check(Valid and (Directions = 15),
        Format('emission %d uses gravity zero and spread 360 for constant-speed travel in all quadrants', [Ord(Emission)]));
    end;
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

procedure CompositionChecks;
const
  W = 320; H = 180;
var
  R, Cold: TFXRenderer;
  Env: TFXEnvironment;
  Sim: TFXSimulator;
  V: TFXVisualList;
  Blank, Pixels, Saved, Other: TFXPixels;
  S, Base, Rebuilt: TFXSettings;
  Material: TFXMaterial;
  Emission: TFXEmission;
  Motion: TFXMotion;
  I, J, LowerArea: Integer;
  Time: Double;
  Valid: Boolean;

  procedure Preview(const Name: string; M: TFXMaterial; E: TFXEmission;
    Movement: TFXMotion; T: Double);
  begin
    S := FXComposeSettings(M, E, Movement);
    R.Render(Blank, W, H, T, S, Pixels);
    SavePNG('compose_' + Name, Pixels, W, H);
  end;

begin
  R := TFXRenderer.Create; Cold := TFXRenderer.Create;
  Env := TFXEnvironment.Create; Sim := TFXSimulator.Create; V := TFXVisualList.Create;
  try
    SetLength(Blank, W * H);
    Valid := True;
    for I := Low(FX_SOURCE_VALUES) to High(FX_SOURCE_VALUES) do
      for J := Low(FX_SOURCE_VALUES) to I - 1 do
        Valid := Valid and (FX_SOURCE_VALUES[I] <> FX_SOURCE_VALUES[J]);
    Check(Valid and (FX_SOURCE_VALUES[2] = feJet) and (FX_SOURCE_VALUES[3] = feExplosion),
      'source list maps named choices to emission values without assuming array indices');

    for Material := Low(TFXMaterial) to High(TFXMaterial) do
      for Emission := Low(TFXEmission) to High(TFXEmission) do
      begin
        Base := FXComposeSettings(Material, Emission, fxmNormal);
        for Motion := Low(TFXMotion) to High(TFXMotion) do
        begin
          S := FXComposeSettings(Material, Emission, Motion);
          Time := 0.2;
          if Emission = feContinuous then Time := 0.5;
          R.Render(Blank, W, H, Time, S, Pixels);
          Env.Prepare(Blank, W, H, S, Time);
          Sim.Generate(Time, S, Env, V);
          Valid := (CountAlpha(Pixels) > 0) and (V.Count > 0) and
            (V.Count <= FX_MAX_PARTICLES * 6) and (S.Emission = Emission) and
            (S.Style = Base.Style) and (S.Shape = Base.Shape) and (S.Color = Base.Color);
          for I := 0 to V.Count - 1 do
            Valid := Valid and not IsNan(V[I].Position.X) and not IsInfinite(V[I].Position.Y) and
              (V[I].Opacity > 0) and (V[I].Opacity <= 1);
          if Motion = fxmWeightless then
            Valid := Valid and (S.Gravity = 0) and (S.Drag = 0) and (S.Sway = 0);
          Check(Valid, Format('composition material=%d emission=%d motion=%d renders visible pixels and preserves its material',
            [Ord(Material), Ord(Emission), Ord(Motion)]));
        end;
      end;
    Check(CountAlpha(Blank) = 0, 'all compositions preserve the transparent input');

    for Motion := fxmWind to fxmStorm do
    begin
      S := FXComposeSettings(fmSnow, feContinuous, Motion);
      R.Render(Blank, W, H, 0.5, S, Pixels);
      LowerArea := 0;
      for I := W * (H * 2 div 3) to High(Pixels) do
        if Pixels[I].A > 16 then Inc(LowerArea);
      Check(LowerArea > 100,
        Format('windy snow motion %d reaches the lower canvas instead of leaving only an upper strip', [Ord(Motion)]));
    end;

    S := FXComposeSettings(fmWater, feContinuous, fxmNormal);
    Check((S.Style = fsRain) and (S.Angle = 0) and S.AutomaticEmitter,
      'water over a wide area selects the existing downward rain profile');
    S := FXComposeSettings(fmWater, feShot, fxmNormal);
    Check((S.Style = fsWater) and (S.Angle = 90) and not S.AutomaticEmitter,
      'a water shot starts at the chosen point and travels right');
    S := FXComposeSettings(fmWater, feJet, fxmNormal);
    Check((S.Style = fsFountain) and (S.Angle = 180) and (S.Gravity > 0) and not S.AutomaticEmitter,
      'continuous water emission selects an upward fountain with downward gravity');

    S := FXComposeSettings(fmSnow, feContinuous, fxmStorm);
    R.Render(Blank, W, H, 0.7345, S, Saved);
    R.Render(Blank, W, H, 1.5, S, Pixels);
    R.Render(Blank, W, H, 0.7345, S, Other);
    Valid := EqualPixels(Saved, Other);
    Cold.Render(Blank, W, H, 0.7345, S, Other);
    Check(Valid and EqualPixels(Saved, Other), 'composed storm motion reproduces fractional reverse seek and a cold cache');
    S := FXComposeSettings(fmSnow, feContinuous, fxmNormal);
    R.Render(Blank, W, H, 0.7345, S, Saved);
    S := FXComposeSettings(fmSnow, feContinuous, fxmVortex);
    R.Render(Blank, W, H, 0.7345, S, Pixels);
    Rebuilt := FXComposeSettings(fmSnow, feContinuous, fxmNormal);
    Cold.Render(Blank, W, H, 0.7345, Rebuilt, Other);
    Check(EqualPixels(Saved, Other) and (Rebuilt.Vortex = 0) and (Rebuilt.Wind = 0) and
      (Rebuilt.Gust = 0) and (Rebuilt.Turbulence = 0),
      'rebuilding normal motion clears previous wind and vortex settings');

    S := FXComposeSettings(fmSnow, feShot, fxmNormal); S.StartTime := 2;
    R.Render(Blank, W, H, 1.9, S, Pixels);
    Check(CountAlpha(Pixels) = 0, 'composed single shots remain absent before their start time');
    R.Render(Blank, W, H, 40, S, Pixels);
    Check(CountAlpha(Pixels) = 0, 'composed single shots expire without leaving old particles');
    S := FXComposeSettings(fmWater, feContinuous, fxmNormal);
    S.InitialState := 0;
    R.Render(Blank, W, H, 0, S, Pixels);
    Check(CountAlpha(Pixels) = 0, 'composed continuous emission still honors an empty initial state');

    Preview('snow_normal', fmSnow, feContinuous, fxmNormal, 0.5);
    Preview('snow_wind', fmSnow, feContinuous, fxmWind, 0.5);
    Preview('snow_storm', fmSnow, feContinuous, fxmStorm, 0.5);
    Preview('water_rain', fmWater, feContinuous, fxmNormal, 0.5);
    Preview('water_shot', fmWater, feShot, fxmNormal, 0.2);
    Preview('water_fountain', fmWater, feJet, fxmNormal, 0.5);
    Preview('petal_vortex', fmPetal, feContinuous, fxmVortex, 0.5);
    Preview('light_explosion', fmLight, feExplosion, fxmNormal, 0.2);
    Preview('slime_weightless', fmSlime, feJet, fxmWeightless, 0.5);
  finally
    V.Free; Sim.Free; Env.Free; Cold.Free; R.Free;
  end;
end;

procedure SlimeChecks;
const
  W = 360; H = 240; M = 120;
var
  Image, Blank, Pixels, Saved, Other, Slope: TFXPixels;
  R, Cold: TFXRenderer;
  Flow: TFXViscousFlow;
  Factory: TFXSimulator;
  Env: TFXEnvironment;
  V: TFXVisualList;
  S, Plain: TFXSettings;
  X, Y, I, Below, ContactCount, Area, K: Integer;
  Mean, VarianceLow, VarianceHigh: Double;
  Valid: Boolean;
  GIF, Decoded: TGIFImage;
  Bitmap: TBitmap;
  Frame: TGIFFrame;
  Control: TGIFGraphicControlExtension;
  Loop: TGIFAppExtNSLoop;
  Row: PBytesRow;
  A, BG, F: Integer;
  P1, P2: TFXParticle;
  Dist, FirstX: Double;

  procedure ConfigureStream;
  begin
    S := FXDefaultSettings(fsSlime); S.Emission := feJet;
    S.AutomaticEmitter := False; S.EmitterY := -90; S.EmitterRange := 100;
    S.Rate := 65; S.Size := 5; S.Depth := 0; S.SizeVariation := 0;
    S.SpeedVariation := 0; S.DirectionSpread := 4; S.Speed := 100;
    S.Gravity := 200; S.DripTime := 0.4; S.AccumAmount := 100;
    S.Prewarm := -1; S.BottomMargin := M;
  end;

  function VelocityVariance: Double;
  var
    J: Integer;
  begin
    Mean := 0;
    for J := 0 to V.Count - 1 do Mean := Mean + V[J].Velocity.X;
    Mean := Mean / Max(1, V.Count); Result := 0;
    for J := 0 to V.Count - 1 do Result := Result + Sqr(V[J].Velocity.X - Mean);
    Result := Result / Max(1, V.Count);
  end;

begin
  SetLength(Image, W * H); SetLength(Blank, W * H);
  for Y := 45 to 184 do
    for X := 70 to 289 do
      if (X < 90) or (X >= 270) or (Y >= 165) then
      begin I := Y * W + X; Image[I].R := 86; Image[I].G := 114; Image[I].B := 145; Image[I].A := 255; end;
  SavePNG('20_slime_source', Image, W, H);
  R := TFXRenderer.Create; Cold := TFXRenderer.Create;
  Factory := TFXSimulator.Create; Flow := TFXViscousFlow.Create(Factory);
  Env := TFXEnvironment.Create; V := TFXVisualList.Create;
  try
    ConfigureStream; Plain := S;
    R.Render(Image, W, H, 0.7, S, Pixels);
    Check((R.OutputWidth = W) and (R.OutputHeight = H + M), 'slime output includes the requested bottom margin');
    SavePNG('21_slime_arriving', Pixels, W, H + M);
    R.Render(Image, W, H, 2.456, S, Saved);
    SavePNG('22_slime_overflow', Saved, W, H + M);
    R.Render(Image, W, H, 4.2, S, Pixels);
    SavePNG('23_slime_dripping', Pixels, W, H + M);
    R.Render(Image, W, H, 2.456, S, Other);
    Check(EqualPixels(Saved, Other), 'viscous reverse seek reproduces an exact fractional frame');
    Cold.Render(Image, W, H, 2.456, S, Other);
    Check(EqualPixels(Saved, Other), 'viscous cold and warm checkpoints produce identical pixels');
    Env.Prepare(Image, W, H, S, 4.2);
    Flow.Generate(4.2, S, Env, V); Below := 0; ContactCount := 0; Valid := True;
    for I := 0 to V.Count - 1 do
    begin
      Valid := Valid and not IsNan(V[I].Position.X) and not IsInfinite(V[I].Position.Y);
      if V[I].IsSplash then
      begin
        Inc(ContactCount);
        if (V[I].Position.Y > 200) and (V[I].Position.X > 100) and (V[I].Position.X < 260) then Inc(Below);
      end;
    end;
    Writeln(Format('SLIME contacts=%d escaped-U=%d', [ContactCount, Below]));
    Check(Valid and (V.Count <= FX_MAX_VISCOUS_PARTICLES), 'viscous particles remain finite and bounded');
    Check((ContactCount > 0) and (Below > 0), 'accumulating slime drains through a concave U instead of remaining fixed');
    Below := 0;
    for Y := H to H + M - 1 do
      for X := 0 to W - 1 do if Pixels[Y * W + X].A > 0 then Inc(Below);
    Check(Below > 0, 'slime remains visible below the original image canvas');

    S := Plain; S.Emission := feShot; S.Burst := 1; S.EmitterRange := 0;
    S.Response := 3;
    Env.Prepare(Image, W, H, S, 1.1); Flow.Generate(1.1, S, Env, V);
    Check(V.Count = 0, 'viscous disappear response removes particles at first contact');
    S.Response := 1; S.Bounce := 0.8;
    Env.Prepare(Image, W, H, S, 1.1); Flow.Generate(1.1, S, Env, V);
    Check((V.Count = 1) and V[0].IsSplash and (V[0].Velocity.Y < 0),
      'viscous reflection response uses the contact normal and bounce strength');

    // 斜面を実際に伝い、接触後も粒子の位置を更新することを確認する。
    SetLength(Slope, W * H);
    for X := 60 to 299 do
      for Y := Round(85 + (X - 60) * 0.4) to Min(H - 1, Round(100 + (X - 60) * 0.4)) do
        Slope[Y * W + X].A := 255;
    S := Plain; S.Emission := feShot; S.Burst := 1; S.EmitterRange := 0;
    S.EmitterX := -80; S.EmitterY := -85; S.DirectionSpread := 0;
    S.DripTime := 5; S.Adhesion := 1; S.Viscosity := 0.5; S.Gravity := 100;
    Env.Prepare(Slope, W, H, S, 0.8); Flow.Generate(0.8, S, Env, V);
    FirstX := 100;
    if V.Count > 0 then FirstX := V[0].Position.X;
    Flow.Generate(1.8, S, Env, V);
    Check((V.Count = 1) and V[0].IsSplash and (V[0].Position.X > FirstX + 2),
      'slime keeps sliding downhill along an alpha slope after contact');

    S := Plain; S.FloorEnabled := True; S.FloorPosition := 75;
    SetLength(Pixels, W * (H + M));
    Env.Prepare(Pixels, W, H + M, S, 3, H);
    Check(SameValue(Env.FloorY, H * 0.75), 'bottom margin leaves the original floor position unchanged');
    S.Collision := False;
    Env.Prepare(Image, W, H, S, 3); Flow.Generate(3, S, Env, V); Valid := True;
    for I := 0 to V.Count - 1 do Valid := Valid and not V[I].IsSplash;
    Check(Valid, 'disabling collision also disables viscous image and floor contact');

    S := Plain; S.Rate := 0; S.Accumulation := False;
    R.Render(Image, W, H, 2, S, Pixels);
    Valid := CompareMem(@Image[0], @Pixels[0], Length(Image) * 4);
    for I := Length(Image) to High(Pixels) do Valid := Valid and (Pixels[I].A = 0);
    Check(Valid, 'bottom padding preserves original pixel positions and transparent empty space');

    S := FXDefaultSettings(fsSlime); S.Emission := feShot; S.Burst := 12;
    S.AutomaticEmitter := False; S.EmitterRange := 120; S.EmitterX := -80;
    S.Speed := 80; S.Angle := 90; S.Gravity := 0; S.Drag := 0;
    S.Depth := 0; S.Size := 1; S.SpeedVariation := 0.8; S.DirectionSpread := 0;
    S.Cohesion := 0; S.Viscosity := 0; S.Prewarm := -1; S.Collision := False;
    Env.Prepare(Blank, W, H, S, 0.12); Flow.Generate(0.12, S, Env, V);
    VarianceLow := VelocityVariance;
    S.Viscosity := 1;
    Env.Prepare(Blank, W, H, S, 0.12); Flow.Generate(0.12, S, Env, V);
    VarianceHigh := VelocityVariance;
    Writeln(Format('SLIME velocity variance low=%.3f high=%.3f', [VarianceLow, VarianceHigh]));
    Check((V.Count = 12) and (VarianceHigh < VarianceLow * 0.8), 'viscosity smooths velocity differences between neighboring particles');
    Check(Mean > 40, 'weightless viscous particles keep moving without artificial downward gravity');
    S.Burst := FX_MAX_PARTICLES; S.MaxSpeed := 50;
    Env.Prepare(Blank, W, H, S, 0.02); Flow.Generate(0.02, S, Env, V); Valid := True;
    for I := 0 to V.Count - 1 do Valid := Valid and (FXLength(V[I].Velocity) <= 50.0001);
    Check((V.Count = FX_MAX_VISCOUS_PARTICLES) and Valid,
      'large viscous bursts respect the particle cap and maximum speed');
    S.Burst := 2; S.Size := 5; S.SizeVariation := 0; S.EmitterRange := 400;
    S.Speed := 0; S.SpeedVariation := 0; S.Viscosity := 0;
    for K := 1 to 1000 do
    begin
      S.Seed := K;
      P1 := Factory.NewParticle(0, 0, S.Lifetime, S, W, H);
      P2 := Factory.NewParticle(1, 0, S.Lifetime, S, W, H);
      Dist := FXLength(FXVec(P1.Position.X - P2.Position.X, P1.Position.Y - P2.Position.Y));
      if (Dist >= 13.1) and (Dist <= 13.3) then Break;
    end;
    X := Round((P1.Position.X + P2.Position.X) * 0.5);
    Y := Round((P1.Position.Y + P2.Position.Y) * 0.5);
    R.Render(Blank, W, H, 0.04, S, Pixels); Area := Pixels[Y * W + X].A;
    S.Cohesion := 1; R.Render(Blank, W, H, 0.04, S, Other);
    Check((CountAlpha(Pixels) > 0) and (Other[Y * W + X].A > Area + 30),
      'cohesion bridges the visible gap between two neighboring slime particles');
    S.DrawMode := 2; R.Render(Blank, W, H, 0.12, S, Pixels);
    Check(CountAlpha(Pixels) = 0, 'viscous contact-only mode hides particles before contact');
    S.DrawMode := 1; R.Render(Blank, W, H, 25, S, Pixels);
    Check(CountAlpha(Pixels) = 0, 'expired slime shots leave no static accumulation behind');
    S.StartTime := 2; R.Render(Blank, W, H, 1, S, Pixels);
    Check(CountAlpha(Pixels) = 0, 'slime shots are absent before their start time');
    // 人物・斜面・段差にも同じソルバーを使う。
    S := FXDefaultSettings(fsSlime); S.BottomMargin := 100; S.AccumAmount := 65;
    R.Render(Source, WIDTH, HEIGHT, 3, S, Pixels);
    SavePNG('24_slime_person', Pixels, WIDTH, HEIGHT + 100);

    if (ParamCount >= 2) and SameText(ParamStr(2), 'animation') then
    begin
      S := Plain; GIF := TGIFImage.Create; Bitmap := TBitmap.Create;
      try
        GIF.ColorReduction := rmQuantize; GIF.DitherMode := dmNearest;
        Bitmap.SetSize(W, H + M);
        for F := 0 to 31 do
        begin
          R.Render(Image, W, H, F * 0.12, S, Pixels);
          Bitmap.PixelFormat := pf32bit;
          for Y := 0 to H + M - 1 do
          begin
            Row := Bitmap.ScanLine[Y];
            for X := 0 to W - 1 do
            begin
              I := Y * W + X; A := Pixels[I].A;
              if ((X div 16 + Y div 16) mod 2) = 0 then BG := 32 else BG := 43;
              Row[X * 4] := (Pixels[I].B * A + (BG + 18) * (255 - A)) div 255;
              Row[X * 4 + 1] := (Pixels[I].G * A + (BG + 8) * (255 - A)) div 255;
              Row[X * 4 + 2] := (Pixels[I].R * A + BG * (255 - A)) div 255;
              Row[X * 4 + 3] := 255;
            end;
          end;
          Frame := GIF.Add(Bitmap);
          Control := TGIFGraphicControlExtension.Create(Frame); Control.Delay := 12;
        end;
        Loop := TGIFAppExtNSLoop.Create(GIF.Images[0]); Loop.Loops := 0;
        GIF.SaveToFile(TPath.Combine(OutputDir, 'slime_demo.gif'));
        Decoded := TGIFImage.Create;
        try
          Decoded.LoadFromFile(TPath.Combine(OutputDir, 'slime_demo.gif'));
          Check(Decoded.Images.Count = 32, 'slime GIF decodes all 32 independent animation frames');
        finally Decoded.Free; end;
      finally Bitmap.Free; GIF.Free; end;

      S := FXDefaultSettings(fsSlime); S.BottomMargin := 100; S.AccumAmount := 65;
      GIF := TGIFImage.Create; Bitmap := TBitmap.Create;
      try
        GIF.ColorReduction := rmQuantize; GIF.DitherMode := dmNearest;
        Bitmap.SetSize(WIDTH div 2, (HEIGHT + 100) div 2);
        for F := 0 to 31 do
        begin
          R.Render(Source, WIDTH, HEIGHT, F * 0.12, S, Pixels);
          Bitmap.PixelFormat := pf32bit;
          for Y := 0 to Bitmap.Height - 1 do
          begin
            Row := Bitmap.ScanLine[Y];
            for X := 0 to Bitmap.Width - 1 do
            begin
              I := Y * 2 * WIDTH + X * 2; A := Pixels[I].A;
              if ((X div 16 + Y div 16) mod 2) = 0 then BG := 32 else BG := 43;
              Row[X * 4] := (Pixels[I].B * A + (BG + 18) * (255 - A)) div 255;
              Row[X * 4 + 1] := (Pixels[I].G * A + (BG + 8) * (255 - A)) div 255;
              Row[X * 4 + 2] := (Pixels[I].R * A + BG * (255 - A)) div 255;
              Row[X * 4 + 3] := 255;
            end;
          end;
          Frame := GIF.Add(Bitmap);
          Control := TGIFGraphicControlExtension.Create(Frame); Control.Delay := 12;
        end;
        Loop := TGIFAppExtNSLoop.Create(GIF.Images[0]); Loop.Loops := 0;
        GIF.SaveToFile(TPath.Combine(OutputDir, 'slime_person_demo.gif'));
        Decoded := TGIFImage.Create;
        try
          Decoded.LoadFromFile(TPath.Combine(OutputDir, 'slime_person_demo.gif'));
          Check(Decoded.Images.Count = 32, 'person slime GIF decodes all 32 independently simulated frames');
        finally Decoded.Free; end;
      finally Bitmap.Free; GIF.Free; end;
    end;
  finally
    V.Free; Env.Free; Flow.Free; Factory.Free; Cold.Free; R.Free;
  end;
end;

procedure SlimeMotionChecks;
var
  Env: TFXEnvironment;
  Factory: TFXSimulator;
  Flow: TFXViscousFlow;
  V: TFXVisualList;
  Previous: TDictionary<Int64, TFXFlowParticle>;
  Particles: TArray<TFXFlowParticle>;
  P, Old: TFXFlowParticle;
  Padded: TFXPixels;
  S: TFXSettings;
  Log: TStringBuilder;
  F, I, Side, UpwardCorrections, InsideSurface: Integer;
  DX, DY, Error, MaxError, MaxSurfaceX, MaxVX, StartX: Double;
  Wall: TFXPixels;
  Valid: Boolean;
begin
  Env := TFXEnvironment.Create; Factory := TFXSimulator.Create;
  Flow := TFXViscousFlow.Create(Factory); V := TFXVisualList.Create;
  Previous := TDictionary<Int64, TFXFlowParticle>.Create;
  Log := TStringBuilder.Create;
  try
    SetLength(Padded, WIDTH * (HEIGHT + 100));
    Move(Source[0], Padded[0], Length(Source) * 4);
    S := FXDefaultSettings(fsSlime); S.BottomMargin := 100; S.AccumAmount := 65;
    Env.Prepare(Padded, WIDTH, HEIGHT + 100, S, 0, HEIGHT);
    MaxError := 0; MaxVX := 0; MaxSurfaceX := 0; UpwardCorrections := 0; InsideSurface := 0;
    Log.AppendLine('time,id,oldphase,phase,x0,y0,x1,y1,vx0,vy0,vx1,vy1,error');
    for F := 0 to 240 do
    begin
      Flow.Generate(F / 60, S, Env, V); Particles := Flow.SnapshotParticles;
      for I := 0 to High(Particles) do
      begin
        P := Particles[I];
        if (P.Phase = fpSurface) and Env.ContainsImage(P.Position) then Inc(InsideSurface);
        if Previous.TryGetValue(P.Particle.ID, Old) then
        begin
          DX := P.Position.X - Old.Position.X; DY := P.Position.Y - Old.Position.Y;
          Error := FXLength(FXVec(DX - P.Velocity.X / 60, DY - P.Velocity.Y / 60));
          if (P.Position.X >= 0) and (P.Position.X < WIDTH) and
            (P.Position.Y >= 0) and (P.Position.Y < HEIGHT + 100) then
          begin
            MaxError := Max(MaxError, Error); MaxVX := Max(MaxVX, Abs(P.Velocity.X));
            if (P.Phase = fpSurface) and (Old.Phase = fpSurface) then
              MaxSurfaceX := Max(MaxSurfaceX, Abs(DX - P.Velocity.X / 60));
            if (DY < -0.5) and (Old.Velocity.Y >= 0) and (P.Velocity.Y >= 0) then Inc(UpwardCorrections);
            if Error > 1 then Log.AppendLine(Format(
              '%.4f,%d,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f',
              [F / 60, P.Particle.ID, Ord(Old.Phase), Ord(P.Phase), Old.Position.X, Old.Position.Y,
               P.Position.X, P.Position.Y, Old.Velocity.X, Old.Velocity.Y,
               P.Velocity.X, P.Velocity.Y, Error], TFormatSettings.Invariant));
          end;
        end;
        Previous.AddOrSetValue(P.Particle.ID, P);
      end;
    end;
    TFile.WriteAllText(TPath.Combine(OutputDir, 'slime_motion.csv'), Log.ToString, TEncoding.UTF8);
    Writeln(Format('SLIME MOTION max-correction=%.3f max-vx=%.3f upward-corrections=%d',
      [MaxError, MaxVX, UpwardCorrections]));
    Writeln(Format('SLIME SURFACE max-lateral-correction=%.3f inside-surface=%d', [MaxSurfaceX, InsideSurface]));
    Check(InsideSurface = 0, 'person sample keeps surface-attached slime outside the opaque image');
    Check(MaxSurfaceX < 4, 'person sample has no repeated lateral transport from surface correction');

    SetLength(Wall, 360 * 240);
    for F := 0 to 239 do
      for I := 140 to 219 do Wall[F * 360 + I].A := 255;
    for Side := -1 to 1 do
    begin
      if Side = 0 then Continue;
      S := FXDefaultSettings(fsSlime); S.Emission := feShot; S.Burst := 1;
      S.AutomaticEmitter := False; S.EmitterRange := 0; S.Depth := 0;
      S.Size := 5; S.SizeVariation := 0; S.Speed := 100; S.SpeedVariation := 0;
      S.DirectionSpread := 0; S.Gravity := 0; S.Drag := 0; S.Cohesion := 0;
      S.Viscosity := 0; S.Prewarm := -1; S.EmitterY := -60;
      if Side < 0 then StartX := 139 else StartX := 221;
      S.EmitterX := StartX - 180; S.Angle := Side * 10;
      Env.Prepare(Wall, 360, 240, S, 0); Valid := True;
      for F := 1 to 45 do
      begin
        Flow.Generate(F / 60, S, Env, V); Particles := Flow.SnapshotParticles;
        if Length(Particles) <> 1 then begin Valid := False; Continue; end;
        Valid := Valid and not Particles[0].Contact and
          ((Particles[0].Position.X - StartX) * Side >= -1E-6);
      end;
      Check(Valid, Format('slime moving away from wall side %d is not pulled inward', [Side]));

      S.EmitterX := Side * 52; S.Angle := -Side * 90;
      Env.Prepare(Wall, 360, 240, S, 0); Flow.Generate(0.5, S, Env, V);
      Particles := Flow.SnapshotParticles;
      Valid := Length(Particles) = 1;
      if Valid then Valid := (Particles[0].Phase = fpSurface) and
        (Particles[0].Normal.X * Side > 0.9) and not Env.ContainsImage(Particles[0].Position);
      Check(Valid, Format('slime approaching wall side %d retains the outward surface normal', [Side]));
    end;
  finally
    Log.Free; Previous.Free; V.Free; Flow.Free; Factory.Free; Env.Free;
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

procedure StartupStateChecks;
const
  Styles: array[0..2] of TFXStyle = (fsRain, fsSnow, fsSlime);
  Names: array[0..2] of string = ('rain', 'snow', 'slime');
var
  R, Cold: TFXRenderer;
  S, Reference: TFXSettings;
  Timing, HalfTiming, ZeroTiming: TFXStartupTiming;
  Pixels, HalfPixels, FullPixels, Saved, Other: TFXPixels;
  Style: TFXStyle;
  I, J, Area0, AreaHalf, AreaFull: Integer;
  Valid: Boolean;
begin
  R := TFXRenderer.Create; Cold := TFXRenderer.Create;
  try
    Valid := True;
    for Style := Low(TFXStyle) to High(TFXStyle) do
    begin
      S := FXDefaultSettings(Style); S.InitialState := 0;
      R.Render(Source, WIDTH, HEIGHT, 0, S, Pixels);
      Valid := Valid and EqualPixels(Source, Pixels);
    end;
    Check(Valid, 'initial state zero starts all twelve styles without particles, contact or accumulation');

    for I := 0 to High(Styles) do
    begin
      S := FXDefaultSettings(Styles[I]); Timing := FXStartupTiming(S, WIDTH, HEIGHT);
      S.InitialState := 50; HalfTiming := FXStartupTiming(S, WIDTH, HEIGHT);
      S.InitialState := 0; ZeroTiming := FXStartupTiming(S, WIDTH, HEIGHT);
      Check((Timing.Prewarm > 0) and SameValue(HalfTiming.Prewarm, Timing.Prewarm * 0.5) and
        (ZeroTiming.Prewarm = 0) and SameValue(ZeroTiming.ParticleLifetime, Timing.ParticleLifetime),
        Names[I] + ': initial progress scales prewarm without shortening particle lifetime');
      S.AccumAmount := 65;
      for J := 0 to 2 do
      begin
        S.InitialState := J * 50;
        R.Render(Source, WIDTH, HEIGHT, 0, S, Pixels);
        SavePNG(Format('startup_%s_%3.3d', [Names[I], J * 50]), Pixels, WIDTH, HEIGHT);
        if J = 1 then HalfPixels := Copy(Pixels);
        if J = 2 then FullPixels := Copy(Pixels);
      end;
      Check(not EqualPixels(HalfPixels, Source) and not EqualPixels(HalfPixels, FullPixels),
        Names[I] + ': state fifty displays a distinct partly progressed initial scene');
      S.InitialState := 0;
      R.Render(Source, WIDTH, HEIGHT, 0, S, Pixels);
      Check(EqualPixels(Source, Pixels), Names[I] + ': changing one hundred back to zero clears the previous initial state');
      R.Render(Source, WIDTH, HEIGHT, 2, S, Pixels);
      Check(not EqualPixels(Source, Pixels), Names[I] + ': particles advance naturally after an empty start');

      S.InitialState := 50;
      R.Render(Source, WIDTH, HEIGHT, 1.2345, S, Saved);
      R.Render(Source, WIDTH, HEIGHT, 3.4, S, Pixels);
      R.Render(Source, WIDTH, HEIGHT, 1.2345, S, Other);
      Valid := EqualPixels(Saved, Other);
      Cold.Render(Source, WIDTH, HEIGHT, 1.2345, S, Other);
      Check(Valid and EqualPixels(Saved, Other), Names[I] + ': partial initial state survives reverse seek and a cold cache');

      S.Wind := 100; S.Gust := 50; S.Turbulence := 10; S.Offset := 0.75;
      R.Render(Source, WIDTH, HEIGHT, 0.25, S, Saved);
      S.Offset := 0;
      Cold.Render(Source, WIDTH, HEIGHT, 1, S, Other);
      Check(EqualPixels(Saved, Other), Names[I] + ': time correction keeps its original seconds and wind clock');

      S := FXDefaultSettings(Styles[I]); S.StartTime := 2.237; S.InitialState := 0;
      R.Render(Source, WIDTH, HEIGHT, S.StartTime, S, Pixels);
      Check(EqualPixels(Source, Pixels), Names[I] + ': a fractional emission start with state zero has no pre-start particles');
      S.InitialState := 100;
      R.Render(Empty, WIDTH, HEIGHT, S.StartTime - 0.1, S, Pixels);
      Check(CountAlpha(Pixels) = 0, Names[I] + ': a prepared continuous effect is hidden before its scheduled start');
      R.Render(Empty, WIDTH, HEIGHT, S.StartTime, S, Pixels);
      Check(CountAlpha(Pixels) > 0, Names[I] + ': scheduled start one hundred displays the prepared state immediately');
    end;

    S := FXDefaultSettings(fsSnow); S.Rate := 0; S.AccumAmount := 100;
    S.InitialState := 0; R.Render(Source, WIDTH, HEIGHT, 0, S, Pixels); Area0 := CountAlpha(Pixels);
    S.InitialState := 50; R.Render(Source, WIDTH, HEIGHT, 0, S, Pixels); AreaHalf := CountAlpha(Pixels);
    S.InitialState := 100; R.Render(Source, WIDTH, HEIGHT, 0, S, FullPixels); AreaFull := CountAlpha(FullPixels);
    Check((Area0 < AreaHalf) and (AreaHalf < AreaFull), 'initial snow accumulation progresses monotonically at zero, fifty and one hundred');
    S.InitialState := 0; Timing := FXStartupTiming(S, WIDTH, HEIGHT);
    R.Render(Source, WIDTH, HEIGHT, Timing.RampTime, S, Pixels);
    Check(EqualPixels(FullPixels, Pixels), 'snow accumulation grows from empty to its existing target amount');
    S.InitialState := 50;
    R.Render(Source, WIDTH, HEIGHT, -Timing.RampTime * 0.25, S, Pixels);
    Reference := S; Reference.InitialState := 100; Reference.AccumAmount := 25;
    Cold.Render(Source, WIDTH, HEIGHT, 0, Reference, Other);
    Check(EqualPixels(Pixels, Other), 'negative time correction can preview the earlier accumulation state');

    S := FXDefaultSettings(fsWater); S.InitialState := 0;
    R.Render(Empty, WIDTH, HEIGHT, 0.4, S, Saved);
    S.InitialState := 100; R.Render(Empty, WIDTH, HEIGHT, 0.4, S, Other);
    Check(EqualPixels(Saved, Other), 'initial state does not advance single-shot emission time');
    S := FXDefaultSettings(fsFountain); S.InitialState := 0;
    R.Render(Empty, WIDTH, HEIGHT, 0.7, S, Saved);
    S.InitialState := 100; R.Render(Empty, WIDTH, HEIGHT, 0.7, S, Other);
    Check(EqualPixels(Saved, Other), 'initial state preserves the existing continuous-jet emission time');
    Check(EqualPixels(Source, SourceCopy), 'startup progress preserves every input RGBA pixel');
  finally
    Cold.Free; R.Free;
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
  Settings := FXDefaultSettings(fsSand); Settings.Angle := 90;
  Settings.Gravity := 0; Settings.Wind := 220; Settings.Rate := Settings.Rate * 3; Settings.Turbulence := 30;
  RenderExample('12_sandstorm', 3, Source);
  Settings := FXDefaultSettings(fsHail);
  RenderExample('13_hail', 2, Source);
  Settings := FXDefaultSettings(fsInk); Settings.AutomaticEmitter := False;
  Settings.EmitterX := -420; Settings.EmitterY := -120;
  RenderExample('14_ink', 0.7, Source);
  Settings := FXDefaultSettings(fsSnow); Settings.Rate := Settings.Rate * 2;
  Settings.Wind := 280; Settings.Gust := 100; Settings.AccumAmount := 65;
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
  Check(DefaultsVisible, 'all twelve styles produce visible standalone effects without manual emitter positioning');
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
  CompositionChecks;
  SlimeChecks;
  SlimeMotionChecks;
  StartupStateChecks;
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
