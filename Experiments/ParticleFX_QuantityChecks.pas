unit ParticleFX_QuantityChecks;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 発生量0の生成・入力画像の保持・演出の重ね合わせと、素材片の滑落を検証する。
// ホストを模擬せず、通常EXEから同じシミュレーターと描画器を呼び出す。

interface

uses ParticleFX_Types;

type
  TQuantityCheck = procedure(Condition: Boolean; const Description: string);
  TQuantitySavePNG = procedure(const Name: string; const Pixels: TFXPixels; W, H: Integer);

// 入力画像を上書きせず、描画量と接触後の位置・速度をCheckへ報告する。
procedure RunQuantityChecks(Check: TQuantityCheck; SavePNG: TQuantitySavePNG);

implementation

uses
  System.Math, System.SysUtils, ParticleFX_Renderer,
  ParticleFX_Collision, ParticleFX_Simulation;

function EqualPixels(const A, B: TFXPixels): Boolean;
begin
  Result := (Length(A) = Length(B)) and (Length(A) > 0);
  if Result then Result := CompareMem(@A[0], @B[0], Length(A) * 4);
end;

procedure InitialDensityChecks(Check: TQuantityCheck; SavePNG: TQuantitySavePNG);
const
  W = 1920; H = 1080;
  Materials: array[0..1] of TFXMaterial = (fmPetal, fmLeaf);
  Motions: array[0..1] of TFXMotion = (fxmFlutter, fxmDance);
  Names: array[0..1] of string = ('petal', 'leaf');
  MotionNames: array[0..1] of string = ('flutter', 'glide');
var
  R, Cold: TFXRenderer;
  Blank, Pixels, Other: TFXPixels;
  S, Before: TFXSettings;
  I, J, K, OldCount, Count, Covered: Integer;
  Counts: array[0..1] of Integer;
  Amount, BurstTrack: Double;
begin
  SetLength(Blank, W * H);
  R := TFXRenderer.Create; Cold := TFXRenderer.Create;
  try
    for I := 0 to 1 do
    begin
      for J := 0 to 1 do
      begin
        S := FXComposeSettings(Materials[I], feContinuous, Motions[J]);
        S.Collision := False; S.Accumulation := False;
        // 変更前は動きによらず素材の毎秒発生数を使っていた。同じ運動・サイズで比較する。
        Before := S; Before.Rate := FXProfile(S.Style).Rate;
        R.Render(Blank, W, H, 0, Before, Pixels);
        OldCount := R.Stats.VisibleParticles;
        SavePNG('density_' + Names[I] + '_' + MotionNames[J] + '_before', Pixels, W, H);
        R.Render(Blank, W, H, 0, S, Pixels);
        Count := R.Stats.VisibleParticles; Counts[J] := Count;
        Covered := 0;
        for K := 0 to High(Pixels) do if Pixels[K].A >= 96 then Inc(Covered);
        SavePNG('density_' + Names[I] + '_' + MotionNames[J] + '_after', Pixels, W, H);
        Amount := S.Rate / FXProfile(S.Style).Rate * 100;
        BurstTrack := S.Burst * 100 / Amount;
        Writeln(Format('INITIAL DENSITY %s %s before=%d after=%d covered=%d amount=%.1f',
          [Names[I], MotionNames[J], OldCount, Count, Covered, Amount], TFormatSettings.Invariant));
        Check((Count >= 10) and (Count <= 140) and (Count < OldCount div 3) and
          (Covered < W * H div 20),
          Names[I] + ' ' + MotionNames[J] + ': actual Full HD initial settings leave a sparse visible field');
        Check((Amount >= 0.1) and (Amount <= 1000) and (BurstTrack <= 12000),
          Names[I] + ' ' + MotionNames[J] + ': initial emission and shot compensation fit the real controls');
        Cold.Render(Blank, W, H, 0, S, Other);
        Check(EqualPixels(Pixels, Other),
          Names[I] + ' ' + MotionNames[J] + ': initial density matches a fresh renderer without a preview rate override');
        R.Render(Blank, W, H, 30, S, Pixels);
        Check(R.Stats.VisibleParticles <= 160,
          Names[I] + ' ' + MotionNames[J] + ': reduced density stays bounded after thirty seconds');
      end;
      Check((Counts[1] <= Counts[0] * 2) and (Counts[0] <= Counts[1] * 2),
        Names[I] + ': flutter and glide initial particle counts remain comparable');
    end;
  finally Cold.Free; R.Free; end;
end;

procedure RunQuantityChecks(Check: TQuantityCheck; SavePNG: TQuantitySavePNG);
const
  W = 384; H = 216;
  Amounts: array[0..4] of Double = (100, 10, 1, 0.1, 0);
  DryStyles: array[0..2] of TFXStyle = (fsPetal, fsLeaf, fsConfetti);
  Seeds: array[0..3] of Cardinal = (1, 2, 99, 12345);
var
  R, Second, Cold: TFXRenderer;
  Env: TFXEnvironment;
  Sim: TFXSimulator;
  V: TFXVisualList;
  Blank, Input, Upstream, Pixels, Other, Terrain: TFXPixels;
  S, Base: TFXSettings;
  Style: TFXStyle;
  Material: TFXMaterial;
  State: TFXCacheEntry;
  Particle: TFXParticle;
  I, J, LastCount, Count: Integer;
  FirstBirth, Time, InitialEnergy, FinalEnergy, Rise, MinimumYSpeed: Double;
  Valid: Boolean;
begin
  SetLength(Blank, W * H); Input := Copy(Blank);
  Input[(H div 2) * W + W div 2].A := 255;
  Input[(H div 2) * W + W div 2].R := 83;
  R := TFXRenderer.Create; Second := TFXRenderer.Create; Cold := TFXRenderer.Create;
  Env := TFXEnvironment.Create; Sim := TFXSimulator.Create; V := TFXVisualList.Create;
  try
    for Style := Low(TFXStyle) to High(TFXStyle) do
    begin
      S := FXDefaultSettings(Style); S.Collision := False; S.Accumulation := False;
      R.Render(Input, W, H, 1, S, Pixels);
      S.Rate := 0;
      R.Render(Input, W, H, 1, S, Pixels);
      Check((R.Stats.VisibleParticles = 0) and EqualPixels(Pixels, Input),
        FXStyleName(Style) + ': zero emission clears cached particles and preserves the input');
    end;
    for Material := fmPetal to fmLeaf do
    begin
      Base := FXComposeSettings(Material, feContinuous, fxmDance);
      Base.Collision := False; Base.Accumulation := False;
      LastCount := High(Integer);
      for I := 0 to High(Amounts) do
      begin
        S := Base; S.Rate := Base.Rate * Amounts[I] / 100;
        R.Render(Blank, W, H, 1, S, Pixels);
        Count := R.Stats.VisibleParticles;
        Cold.Render(Blank, W, H, 1, S, Other);
        Check((Count <= LastCount) and EqualPixels(Pixels, Other),
          Format('material %d emission %.1f percent decreases live particles without stale images',
            [Ord(Material), Amounts[I]], TFormatSettings.Invariant));
        LastCount := Count;
      end;
    end;

    S := FXComposeSettings(fmPetal, feContinuous, fxmFlutter);
    S.Collision := False; S.Accumulation := False;
    R.Render(Blank, W, H, 1, S, Upstream);
    S.Rate := 0;
    Second.Render(Upstream, W, H, 1, S, Pixels);
    Check((Second.Stats.VisibleParticles = 0) and EqualPixels(Upstream, Pixels) and
      not EqualPixels(Blank, Pixels), 'zero in a later effect preserves particles already drawn by an earlier effect');
    R.Render(Blank, W, H, 1, S, Upstream);
    Second.Render(Upstream, W, H, 1, S, Pixels);
    Check(EqualPixels(Blank, Pixels), 'setting both layered effects to zero removes all airborne particles');

    S := FXDefaultSettings(fsPetal);
    S.Rate := 0.001; S.Prewarm := -1; S.InitialState := 0;
    S.Collision := False; S.Accumulation := False; S.AutomaticEmitter := False;
    S.Speed := 0; S.Gravity := 0; S.Sway := 0;
    S.AutomaticLifetime := False; S.Lifetime := 10;
    FirstBirth := FXRandom(0, S.Seed, 20) * 0.9 / 0.01;
    Env.Prepare(Blank, W, H, S, FirstBirth + 0.01);
    Sim.Generate(FirstBirth + 0.01, S, Env, V);
    Check(V.Count = 0, 'very low emission does not silently round up to 0.01 particles per second');
    FirstBirth := FXRandom(0, S.Seed, 20) * 0.9 / S.Rate;
    Sim.Generate(FirstBirth + 0.01, S, Env, V);
    Check(V.Count = 1, 'very low emission still emits at its actual deterministic birth time');

    for J := 0 to High(Seeds) do
    begin
      S := FXComposeSettings(fmPetal, feContinuous, fxmDance);
      S.Emission := feShot; S.Burst := 128; S.AutomaticEmitter := False; S.EmitterRange := 0;
      S.Collision := False; S.Accumulation := False; S.Seed := Seeds[J];
      S.AutomaticLifetime := False; S.Lifetime := 120;
      Env.Prepare(Blank, W, H, S, 90);
      Sim.Generate(90, S, Env, V);
      Valid := True;
      for I := 0 to 127 do
      begin
        Particle := Sim.NewParticle(I, 0, S.Lifetime, S, W, H);
        if not Sim.SnapshotParticle(I, State) then begin Valid := False; Continue; end;
        InitialEnergy := Sqr(FXLength(Particle.Velocity)) * 0.5 - S.Gravity * Particle.Position.Y;
        FinalEnergy := Sqr(FXLength(State.Velocity)) * 0.5 - S.Gravity * State.Position.Y;
        Valid := Valid and (State.Position.Y > Particle.Position.Y + 200) and
          (FinalEnergy <= InitialEnergy + 5) and (State.Glide.Cycle >= 3);
      end;
      Check(Valid, Format('128 glide particles with seed %d descend over 90 seconds without gaining energy', [Seeds[J]]));
    end;

    SetLength(Terrain, 256 * 256);
    for I := 160 * 256 to High(Terrain) do Terrain[I].A := 255;
    for J := 0 to High(DryStyles) do
    begin
      S := FXDefaultSettings(DryStyles[J]);
      S.Emission := feShot; S.Burst := 1; S.AutomaticEmitter := False;
      S.EmitterRange := 0; S.EmitterY := -60; S.Angle := 0; S.DirectionSpread := 0;
      S.SizeVariation := 0; S.SpeedVariation := 0; S.Depth := 0; S.Sway := 0;
      S.AutomaticLifetime := False; S.Lifetime := 10;
      S.Gravity := 3; S.ContactLife := 5; S.Accumulation := False;
      Env.Prepare(Terrain, 256, 256, S, 2);
      Valid := True; Rise := 0; MinimumYSpeed := 0;
      for I := 0 to 180 do
      begin
        Time := 2 + I / 60;
        Sim.Generate(Time, S, Env, V);
        if not Sim.SnapshotParticle(0, State) or not State.Hit or (V.Count <> 1) then
        begin Valid := False; Continue; end;
        Valid := Valid and V[0].IsSplash and
          (V[0].Velocity.Y >= -1E-6);
        Rise := Max(Rise, State.HitPosition.Y - V[0].Position.Y);
        MinimumYSpeed := Min(MinimumYSpeed, V[0].Velocity.Y);
      end;
      Writeln(Format('DRY CONTACT style=%d rise=%.6f min-vy=%.6f', [Ord(DryStyles[J]), Rise, MinimumYSpeed]));
      Check(Valid and (Rise <= S.Size * 0.65 + 1.5),
        FXStyleName(DryStyles[J]) + ': automatic sliding never launches the piece upward from a flat surface');
      S.Response := 1;
      Sim.Generate(2, S, Env, V);
      Check((V.Count = 1) and V[0].IsSplash and (V[0].Velocity.Y < 0),
        FXStyleName(DryStyles[J]) + ': explicitly selected bounce keeps its reflected motion');
    end;
    InitialDensityChecks(Check, SavePNG);
  finally
    V.Free; Sim.Free; Env.Free; Cold.Free; Second.Free; R.Free;
  end;
end;

end.
