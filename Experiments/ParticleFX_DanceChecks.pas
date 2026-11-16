unit ParticleFX_DanceChecks;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 素材と動きの組み合わせを描き、滑空・浮上・失速と全体の落下を検証する。
// SDKを読み込まず、位置・速度のCSVと比較用PNG/GIFを検証先へ出力する。

interface

uses ParticleFX_Types;

type
  TDanceCheck = procedure(Condition: Boolean; const Description: string);
  TDanceSavePNG = procedure(const Name: string; const Pixels: TFXPixels; W, H: Integer);

// COM初期化済みの呼出元で実行する。描画器の保存データや元画像を変更しない。
procedure RunDanceChecks(const OutputDir: string; Check: TDanceCheck;
  SavePNG: TDanceSavePNG; Animation: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.Math, System.IOUtils,
  Winapi.Windows, Vcl.Graphics, Vcl.Imaging.GIFImg,
  ParticleFX_Collision, ParticleFX_Simulation, ParticleFX_Renderer, ParticleFX_Motion;

const
  CASE_MATERIALS: array[0..3] of TFXMaterial = (fmPetal, fmPetal, fmLeaf, fmLeaf);
  CASE_MOTIONS: array[0..3] of TFXMotion = (fxmFlutter, fxmDance, fxmFlutter, fxmDance);
  CASE_NAMES: array[0..3] of string = ('桜：ヒラヒラ', '桜：舞う', '落ち葉：ヒラヒラ', '落ち葉：舞う');

function EqualPixels(const A, B: TFXPixels): Boolean;
begin
  Result := (Length(A) = Length(B)) and (Length(A) > 0);
  if Result then Result := CompareMem(@A[0], @B[0], Length(A) * 4);
end;

function CountAlpha(const Image: TFXPixels): Integer;
var P: TFXPixelRGBA;
begin
  Result := 0;
  for P in Image do if P.A > 0 then Inc(Result);
end;

procedure DanceAnimation(const OutputDir: string; Check: TDanceCheck);
const W = 320; H = 240; Header = 26; Frames = 64;
type
  TRow = array[0..W * 8 - 1] of Byte;
  PRow = ^TRow;
var
  Renderers: array[0..3] of TFXRenderer;
  GIF, Decoded: TGIFImage;
  Bitmap: TBitmap;
  Frame: TGIFFrame;
  Control: TGIFGraphicControlExtension;
  Loop: TGIFAppExtNSLoop;
  Blank, Pixels: TFXPixels;
  S: TFXSettings;
  CaseIndex: Integer;
  F, X, Y, I, OX, OY, A, BG: Integer;
  Row: PRow;
begin
  SetLength(Blank, W * H);
  for CaseIndex := 0 to 3 do Renderers[CaseIndex] := TFXRenderer.Create;
  GIF := TGIFImage.Create; Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(W * 2, (H + Header) * 2);
    GIF.ColorReduction := rmQuantize; GIF.DitherMode := dmNearest;
    for F := 0 to Frames - 1 do
    begin
      Bitmap.PixelFormat := pf32bit;
      Bitmap.Canvas.Brush.Color := RGB(16, 27, 43);
      Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
      Bitmap.Canvas.Font.Name := 'Yu Gothic UI';
      Bitmap.Canvas.Font.Color := clWhite; Bitmap.Canvas.Font.Size := 10;
      for CaseIndex := 0 to 3 do
      begin
        S := FXComposeSettings(CASE_MATERIALS[CaseIndex], feContinuous, CASE_MOTIONS[CaseIndex]);
        S.Accumulation := False; S.Collision := False;
        Renderers[CaseIndex].Render(Blank, W, H, 2 + F * 0.08, S, Pixels);
        OX := (CaseIndex mod 2) * W; OY := (CaseIndex div 2) * (H + Header);
        Bitmap.Canvas.TextOut(OX + 8, OY + 3, CASE_NAMES[CaseIndex]);
        for Y := 0 to H - 1 do
        begin
          Row := Bitmap.ScanLine[OY + Header + Y];
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
    GIF.SaveToFile(TPath.Combine(OutputDir, 'sakura_leaf_motion.gif'));
    Decoded := TGIFImage.Create;
    try
      Decoded.LoadFromFile(TPath.Combine(OutputDir, 'sakura_leaf_motion.gif'));
      Check((Decoded.Images.Count = Frames) and (Decoded.Width = W * 2) and
        (Decoded.Height = (H + Header) * 2), 'gliding and flutter GIF decodes all 64 comparison frames');
    finally Decoded.Free; end;
  finally
    Bitmap.Free; GIF.Free;
    for CaseIndex := 0 to 3 do Renderers[CaseIndex].Free;
  end;
end;

procedure RunDanceChecks(const OutputDir: string; Check: TDanceCheck;
  SavePNG: TDanceSavePNG; Animation: Boolean);
const W = 640; H = 360;
var
  R, Cold: TFXRenderer;
  Sim: TFXSimulator;
  Env: TFXEnvironment;
  V: TFXVisualList;
  S, Natural: TFXSettings;
  Blank, Obstacle, Pixels, Saved, Other: TFXPixels;
  State, Previous: TFXCacheEntry;
  Glide: TFXGlideState;
  Velocity: TFXVec;
  CaseIndex, I, Up, Down, Stalls, Faster, Slower, SameDirection, ChangedDirection,
    TopArea, BottomArea: Integer;
  Speed, PreviousSpeed, Maximum, FirstY, LastY, LastStallY, Energy, InitialEnergy, Age: Double;
  Valid, LowerPeaks, NoEnergyGain: Boolean;
  CSV: TStringBuilder;
begin
  SetLength(Blank, W * H);
  R := TFXRenderer.Create; Cold := TFXRenderer.Create;
  Sim := TFXSimulator.Create; Env := TFXEnvironment.Create; V := TFXVisualList.Create;
  CSV := TStringBuilder.Create;
  try
    CSV.AppendLine('case,time,x,y,vx,vy,angle,cycle,stalled,direction,energy');
    for CaseIndex := 0 to 3 do
    begin
      S := FXComposeSettings(CASE_MATERIALS[CaseIndex], feContinuous, CASE_MOTIONS[CaseIndex]);
      Valid := (S.Emission = feContinuous) and (S.Shape in [shPetal, shLeaf]) and (S.Angle = 0);
      if CASE_MOTIONS[CaseIndex] = fxmDance then
        Valid := Valid and (S.GlideStrength > 0) and (S.Gravity > 0) and (S.Speed > 0) and (S.Sway = 0)
      else Valid := Valid and (S.GlideStrength = 0) and (S.Sway > 0) and (S.Speed > 0);
      R.Render(Blank, W, H, 0.7345, S, Saved);
      Check(Valid and (CountAlpha(Saved) > 100), CASE_NAMES[CaseIndex] + ': visible top-down material and motion');
      SavePNG('motion_' + IntToStr(CaseIndex), Saved, W, H);
      R.Render(Blank, W, H, 1.7, S, Pixels);
      R.Render(Blank, W, H, 0.7345, S, Other);
      Cold.Render(Blank, W, H, 0.7345, S, Pixels);
      Check(EqualPixels(Saved, Other) and EqualPixels(Saved, Pixels),
        CASE_NAMES[CaseIndex] + ': exact fractional reverse seek and cold reproduction');
      S.InitialState := 0;
      R.Render(Blank, W, H, 0, S, Pixels);
      Check(CountAlpha(Pixels) = 0, CASE_NAMES[CaseIndex] + ': empty initial state is preserved');
      S.InitialState := 100; S.StartTime := 2;
      R.Render(Blank, W, H, 1.99, S, Pixels);
      Check(CountAlpha(Pixels) = 0, CASE_NAMES[CaseIndex] + ': scheduled start has no early particles');
      if CASE_MOTIONS[CaseIndex] <> fxmDance then Continue;

      S := FXComposeSettings(CASE_MATERIALS[CaseIndex], feContinuous, fxmDance);
      S.Emission := feShot; S.Burst := 1; S.AutomaticEmitter := False;
      S.EmitterRange := 0; S.Collision := False; S.Accumulation := False;
      S.Depth := 0; S.SizeVariation := 0; S.SpeedVariation := 0; S.DirectionSpread := 0;
      S.AutomaticLifetime := False; S.Lifetime := 40;
      Env.Prepare(Blank, W, H, S, 0);
      Up := 0; Down := 0; Stalls := 0; Faster := 0; Slower := 0;
      SameDirection := 0; ChangedDirection := 0; Maximum := 0; PreviousSpeed := -1;
      FirstY := 0; LastY := 0; LastStallY := -1E10;
      InitialEnergy := Sqr(S.Speed) * 0.5 - S.Gravity * H * 0.5;
      Previous := Default(TFXCacheEntry); Valid := True; LowerPeaks := True; NoEnergyGain := True;
      for I := 1 to 1800 do
      begin
        Age := I / 60;
        Sim.Generate(Age, S, Env, V);
        if not Sim.SnapshotParticle(0, State) then begin Valid := False; Continue; end;
        Speed := FXLength(State.Velocity); Maximum := Max(Maximum, Speed);
        if I = 1 then FirstY := State.Position.Y;
        LastY := State.Position.Y;
        if State.Velocity.Y < -5 then Inc(Up);
        if State.Velocity.Y > 5 then Inc(Down);
        if PreviousSpeed >= 0 then
        begin
          if Speed > PreviousSpeed + 0.1 then Inc(Faster);
          if Speed < PreviousSpeed - 0.1 then Inc(Slower);
        end;
        if State.Glide.Cycle > Previous.Glide.Cycle then
        begin
          Inc(Stalls);
          LowerPeaks := LowerPeaks and (State.Position.Y > LastStallY + 1);
          LastStallY := State.Position.Y;
          if State.Glide.Direction = Previous.Glide.Direction then Inc(SameDirection)
          else Inc(ChangedDirection);
        end;
        Energy := Speed * Speed * 0.5 - S.Gravity * State.Position.Y;
        NoEnergyGain := NoEnergyGain and (Energy <= InitialEnergy + 5);
        CSV.AppendLine(Format('%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%.6f',
          [CaseIndex, Age, State.Position.X, State.Position.Y, State.Velocity.X,
          State.Velocity.Y, State.Glide.Angle, State.Glide.Cycle, Ord(State.Glide.Stalled),
          State.Glide.Direction, Energy], TFormatSettings.Invariant));
        Previous := State; PreviousSpeed := Speed;
      end;
      Check(Valid and (Up > 100) and (Down > 100) and (Stalls >= 4) and
        (Faster > 100) and (Slower > 100) and (Maximum > 80),
        CASE_NAMES[CaseIndex] + ': gravity accelerates each dive and lift returns it upward before a stall');
      Check(LowerPeaks and (LastY > FirstY + 200),
        CASE_NAMES[CaseIndex] + ': arc peaks lose height and the particle ultimately falls');
      Check((SameDirection > 0) and (ChangedDirection > 0),
        CASE_NAMES[CaseIndex] + ': stalls can retain or reverse the next gliding direction');
      Check(NoEnergyGain, CASE_NAMES[CaseIndex] + ': motion never exceeds its initial mechanical energy');

      S.MaxSpeed := 8; Maximum := 0;
      for I := 1 to 240 do
      begin
        Sim.Generate(I / 60, S, Env, V);
        if Sim.SnapshotParticle(0, State) then Maximum := Max(Maximum, FXLength(State.Velocity));
      end;
      Check(Maximum <= 8.001, CASE_NAMES[CaseIndex] + ': glide respects maximum speed');
      S.MaxSpeed := 2400; S.GravityAngle := 90;
      Sim.Generate(8, S, Env, V);
      Check(Sim.SnapshotParticle(0, State) and (State.Position.X > W * 0.5 + 30),
        CASE_NAMES[CaseIndex] + ': net descent follows rotated gravity');
      S.GravityAngle := 0; S.Collision := True; S.Response := 3;
      Obstacle := Copy(Blank);
      for I := 0 to W - 1 do Obstacle[260 * W + I].A := 255;
      Env.Prepare(Obstacle, W, H, S, 10);
      Sim.Generate(10, S, Env, V);
      Check((Sim.CollisionCount > 0) and (V.Count = 0),
        CASE_NAMES[CaseIndex] + ': gliding descent collides with a one-pixel floor');
    end;
    TFile.WriteAllText(TPath.Combine(OutputDir, 'glide_motion.csv'), CSV.ToString, TEncoding.UTF8);
    S := FXComposeSettings(fmPetal, feContinuous, fxmDance);
    Glide := Default(TFXGlideState); Velocity := FXVec(100, 80); Maximum := FXLength(Velocity);
    Valid := True;
    for I := 0 to 600 do
    begin
      Speed := FXLength(Velocity);
      FXTurnGlide(0, 1, 1 / 60, S, Glide, Velocity);
      Valid := Valid and (FXLength(Velocity) <= Speed + 1E-6);
    end;
    Check(Valid and (FXLength(Velocity) <= Maximum + 1E-6),
      'lift rotates velocity and stalls dissipate it without supplying propulsion');
    Natural := FXComposeSettings(fmPetal, feContinuous, fxmNormal);
    Natural.Rate := FXComposeSettings(fmPetal, feContinuous, fxmFlutter).Rate;
    R.Render(Blank, W, H, 1, Natural, Saved);
    R.Render(Blank, W, H, 1, S, Pixels);
    S := FXComposeSettings(fmPetal, feContinuous, fxmFlutter);
    R.Render(Blank, W, H, 1, S, Other);
    Check((S.GlideStrength = 0) and EqualPixels(Saved, Other),
      'flutter motion is unchanged at equal emission and clears previously selected gliding motion');
    S := FXComposeSettings(fmLeaf, feContinuous, fxmDance);
    SetLength(Blank, 1920 * 1080);
    R.Render(Blank, 1920, 1080, 0, S, Pixels);
    TopArea := 0; BottomArea := 0;
    for I := 0 to High(Pixels) do
      if Pixels[I].A > 96 then
      begin
        if I < 1920 * 360 then Inc(TopArea);
        if I >= 1920 * 720 then Inc(BottomArea);
      end;
    Check((TopArea > 100) and (BottomArea > 100), 'Full HD gliding prewarm fills upper and lower regions');
    Check(CountAlpha(Blank) = 0, 'all material and motion checks preserve the input pixels');
    if Animation then DanceAnimation(OutputDir, Check);
  finally
    CSV.Free; V.Free; Env.Free; Sim.Free; Cold.Free; R.Free;
  end;
end;

end.
