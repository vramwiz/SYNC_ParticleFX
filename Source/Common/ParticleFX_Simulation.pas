unit ParticleFX_Simulation;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 発生時刻を基準とする固定刻みの運動・接触・飛散を計算する。
// キャッシュは整数刻みの状態だけを保持し、逆シークでは発生時刻から再計算する。

interface

uses
  System.Generics.Collections, ParticleFX_Types, ParticleFX_Collision, ParticleFX_Motion;

type
  TFXParticle = record
    ID: Int64;
    Birth, Size, Depth, Phase, Spin, Life: Double;
    Position, Velocity: TFXVec;
    Color: Cardinal;
  end;

  TFXCacheEntry = record
    Position, Velocity, HitPosition, HitVelocity, Normal: TFXVec;
    Glide: TFXGlideState;
    Step: Integer;
    Hit: Boolean;
    HitTime: Double;
  end;

  TFXSimulator = class
  private
    FCache: TDictionary<Int64, TFXCacheEntry>;
    FSettings: TFXSettings;
    FRevision: Integer;
    FPrepared: Boolean;
    FSimulatedSteps, FCollisionCount: Integer;
    procedure Advance(var State: TFXCacheEntry; const P: TFXParticle;
      const S: TFXSettings; Environment: TFXEnvironment; Age, DT: Double);
    procedure RenderParticle(const P: TFXParticle; Age: Double;
      const S: TFXSettings; Environment: TFXEnvironment; Output: TFXVisualList);
    procedure ContactVisuals(const P: TFXParticle; const State: TFXCacheEntry;
      Age: Double; const S: TFXSettings; Environment: TFXEnvironment; Output: TFXVisualList);
  public
    // 共通の発生条件から初期粒子を返す。シミュレーターの履歴は変更しない。
    function NewParticle(ID: Int64; Birth, Lifetime: Double; const S: TFXSettings;
      Width, Height: Integer): TFXParticle;
    constructor Create;
    destructor Destroy; override;
    // 任意時刻の描画要素を生成する。Outputの要素を置換し、粒子総数に上限を設ける。
    // 逆再生・キャッシュなし・同一時刻の再計算でも同じ固定刻みを使用する。
    procedure Generate(Time: Double; const Settings: TFXSettings;
      Environment: TFXEnvironment; Output: TFXVisualList);
    // 診断用に整数刻みの状態を値で返す。描画範囲外でも追跡でき、履歴は変更しない。
    function SnapshotParticle(ID: Int64; out State: TFXCacheEntry): Boolean;
    property SimulatedSteps: Integer read FSimulatedSteps;
    property CollisionCount: Integer read FCollisionCount;
  end;

implementation

uses
  System.Math, System.SysUtils;

const
  SIM_DT = 1.0 / 60.0;

constructor TFXSimulator.Create;
begin
  inherited;
  FCache := TDictionary<Int64, TFXCacheEntry>.Create;
end;

destructor TFXSimulator.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TFXSimulator.SnapshotParticle(ID: Int64; out State: TFXCacheEntry): Boolean;
begin
  Result := FCache.TryGetValue(ID, State);
  if not Result then State := Default(TFXCacheEntry);
end;

function TFXSimulator.NewParticle(ID: Int64; Birth, Lifetime: Double; const S: TFXSettings;
  Width, Height: Integer): TFXParticle;
var
  D, Tangent: TFXVec;
  Extent, Span, Angle, Speed, Radius, A: Double;
begin
  Result := Default(TFXParticle);
  Result.ID := ID; Result.Birth := Birth;
  Result.Depth := 1 - S.Depth * 0.65 + FXRandom(ID, S.Seed, 1) * S.Depth;
  Result.Size := Max(0.25, S.Size * Result.Depth *
    (1 + (FXRandom(ID, S.Seed, 2) - 0.5) * S.SizeVariation));
  Result.Phase := FXRandom(ID, S.Seed, 3) * 2 * Pi;
  Result.Spin := S.Rotation * (FXRandom(ID, S.Seed, 4) * 2 - 1);
  Result.Life := Max(0.05, Lifetime * (0.85 + FXRandom(ID, S.Seed, 5) * 0.3));
  Angle := S.Angle + (FXRandom(ID, S.Seed, 6) - 0.5) * S.DirectionSpread;
  D := FXDirection(S.Angle);
  Tangent := FXVec(D.Y, -D.X);
  Result.Position := FXVec(Width * 0.5 + S.EmitterX, Height * 0.5 + S.EmitterY);
  if (S.Emission = feContinuous) or
    (S.AutomaticEmitter and (S.Emission in [feShot, feJet, feSpray])) then
  begin
    // 進行方向と反対の画面外へ発生線を置く。斜め方向も同じ投影式で扱う。
    Extent := (Abs(D.X) * Width + Abs(D.Y) * Height) * 0.5 + Result.Size * 4 + 4;
    Span := 0;
    if S.Emission = feContinuous then
      Span := (Abs(Tangent.X) * Width + Abs(Tangent.Y) * Height) *
        (FXRandom(ID, S.Seed, 7) - 0.5) * S.EmitterRange / 100;
    if S.AutomaticEmitter then
    begin
      Result.Position.X := Result.Position.X - D.X * Extent;
      Result.Position.Y := Result.Position.Y - D.Y * Extent;
    end;
    Result.Position.X := Result.Position.X + Tangent.X * Span;
    Result.Position.Y := Result.Position.Y + Tangent.Y * Span;
    if S.AutomaticEmitter and S.FloorEnabled and (D.Y < -0.3) then
      Result.Position.Y := Min(Result.Position.Y, S.FloorPosition / 100 * Height - Result.Size * 2 - 1);
  end;
  if S.Emission <> feContinuous then
  begin
    A := FXRandom(ID, S.Seed, 8) * 2 * Pi;
    Radius := Sqrt(FXRandom(ID, S.Seed, 9)) * S.EmitterRange * 0.025;
    Result.Position.X := Result.Position.X + Cos(A) * Radius;
    Result.Position.Y := Result.Position.Y + Sin(A) * Radius;
  end;
  D := FXDirection(Angle);
  Speed := S.Speed * Result.Depth * (1 + (FXRandom(ID, S.Seed, 10) - 0.5) * S.SpeedVariation);
  Result.Velocity := FXVec(D.X * Speed, D.Y * Speed);
  Result.Color := FXParticleColor(S, ID);
end;

procedure TFXSimulator.Advance(var State: TFXCacheEntry; const P: TFXParticle;
  const S: TFXSettings; Environment: TFXEnvironment; Age, DT: Double);
var
  Gravity, Wind, Accel, Next, Hit, Normal, PreviousVelocity: TFXVec;
  Gust, AbsoluteTime, Wave, Omega, Speed, Rotation, CS, SN, VX, Fraction: Double;
begin
  if State.Hit or (DT <= 0) then Exit;
  PreviousVelocity := State.Velocity;
  Gravity := FXDirection(S.GravityAngle);
  Wind := FXDirection(S.WindAngle);
  AbsoluteTime := P.Birth + Age;
  Gust := 0;
  if S.Gust > 0 then
    Gust := S.Gust * (Sin(AbsoluteTime * 2 * Pi / S.GustPeriod) * 0.65 +
      Sin(AbsoluteTime * 2 * Pi / (S.GustPeriod * 1.713) + 1.7) * 0.35);
  Accel := FXVec(Gravity.X * S.Gravity + Wind.X * (S.Wind + Gust),
    Gravity.Y * S.Gravity + Wind.Y * (S.Wind + Gust));
  if S.Turbulence > 0 then
  begin
    Wave := AbsoluteTime * 2 * Pi / S.TurbulencePeriod + P.Phase;
    Accel.X := Accel.X + S.Turbulence * (Sin(Wave) + 0.45 * Sin(Wave * 1.71));
    Accel.Y := Accel.Y + S.Turbulence * (Cos(Wave * 0.83) + 0.4 * Cos(Wave * 1.37));
  end;
  if S.Sway > 0 then
  begin
    Omega := S.SwaySpeed * 1.6;
    Wave := -S.Sway * Sqr(Omega) * Sin(Age * Omega + P.Phase);
    Accel.X := Accel.X + Gravity.Y * Wave;
    Accel.Y := Accel.Y - Gravity.X * Wave;
  end;
  State.Velocity.X := (State.Velocity.X + Accel.X * DT) * Exp(-S.Drag * DT);
  State.Velocity.Y := (State.Velocity.Y + Accel.Y * DT) * Exp(-S.Drag * DT);
  if S.Vortex <> 0 then
  begin
    Rotation := DegToRad(S.Vortex) * DT;
    CS := Cos(Rotation); SN := Sin(Rotation); VX := State.Velocity.X;
    State.Velocity.X := VX * CS - State.Velocity.Y * SN;
    State.Velocity.Y := VX * SN + State.Velocity.Y * CS;
  end;
  if S.GlideStrength > 0 then
    FXTurnGlide(P.ID, P.Depth, DT, S, State.Glide, State.Velocity);
  Speed := FXLength(State.Velocity);
  if Speed > S.MaxSpeed then
  begin
    State.Velocity.X := State.Velocity.X * S.MaxSpeed / Speed;
    State.Velocity.Y := State.Velocity.Y * S.MaxSpeed / Speed;
  end;
  if S.GlideStrength > 0 then
    Next := FXVec(State.Position.X + (PreviousVelocity.X + State.Velocity.X) * 0.5 * DT,
      State.Position.Y + (PreviousVelocity.Y + State.Velocity.Y) * 0.5 * DT)
  else Next := FXVec(State.Position.X + State.Velocity.X * DT,
    State.Position.Y + State.Velocity.Y * DT);
  if S.Collision and Environment.Trace(State.Position, Next, P.Size * 0.65,
    Hit, Normal, Fraction) then
  begin
    State.Hit := True; State.HitTime := Age + DT * Fraction;
    State.HitPosition := Hit; State.Normal := Normal; State.HitVelocity := State.Velocity;
  end else State.Position := Next;
  Inc(FSimulatedSteps);
end;

procedure TFXSimulator.ContactVisuals(const P: TFXParticle; const State: TFXCacheEntry;
  Age: Double; const S: TFXSettings; Environment: TFXEnvironment; Output: TFXVisualList);
var
  I, Count, Response: Integer;
  T, Life, Angle, Speed, Dot, Fade, ImpactScale: Double;
  V: TFXVisual;
  N, Tangent, Direction, Gravity, Reflected: TFXVec;
  function Flight(const Origin, InitialVelocity: TFXVec; Radius: Double;
    AllowBounce: Boolean; out Position, Velocity: TFXVec): Boolean;
  var
    Step, Steps, Bounces: Integer;
    DT, Dot, Fraction, CurrentSpeed: Double;
    Next, Hit, HitNormal: TFXVec;
  begin
    Result := True; Position := Origin; Velocity := InitialVelocity; Bounces := 0;
    Steps := Floor(T / SIM_DT);
    for Step := 0 to Steps do
    begin
      DT := Min(SIM_DT, Max(0.0, T - Step * SIM_DT));
      if DT <= 0 then Break;
      Velocity.X := Velocity.X + Gravity.X * S.Gravity * DT;
      Velocity.Y := Velocity.Y + Gravity.Y * S.Gravity * DT;
      CurrentSpeed := FXLength(Velocity);
      if CurrentSpeed > S.MaxSpeed then
        Velocity := FXVec(Velocity.X * S.MaxSpeed / CurrentSpeed, Velocity.Y * S.MaxSpeed / CurrentSpeed);
      Next := FXVec(Position.X + Velocity.X * DT, Position.Y + Velocity.Y * DT);
      if S.Collision and Environment.Trace(Position, Next, Radius, Hit, HitNormal, Fraction) then
      begin
        if not AllowBounce then Exit(False);
        Position := FXVec(Hit.X + HitNormal.X * 1.1, Hit.Y + HitNormal.Y * 1.1);
        Dot := FXDot(Velocity, HitNormal);
        if Response = 5 then
        begin
          // 素材片の滑落では面へ入る成分だけを除き、上向きの反射を作らない。
          if Dot < 0 then Velocity := FXVec(Velocity.X - Dot * HitNormal.X,
            Velocity.Y - Dot * HitNormal.Y);
        end else
          Velocity := FXVec((Velocity.X - 2 * Dot * HitNormal.X) * S.Bounce * 0.7,
            (Velocity.Y - 2 * Dot * HitNormal.Y) * S.Bounce * 0.7);
        Inc(Bounces);
        if (Bounces >= 3) or (FXLength(Velocity) < 8) then Break;
      end else Position := Next;
    end;
  end;
begin
  Inc(FCollisionCount);
  T := Max(0.0, Age - State.HitTime);
  Life := S.ContactLife;
  if T > Max(1.5, Life) then Exit;
  Response := S.Response;
  if Response = 0 then
    case S.Style of
      fsRain, fsWater, fsFountain: Response := 4;
      fsHail: Response := 1;
      fsSnow, fsSand, fsInk: Response := 2;
      fsPetal, fsLeaf, fsConfetti: Response := 5;
      fsSpark: Response := 4;
    end;
  if Response = 3 then Exit;
  N := State.Normal; Tangent := FXVec(-N.Y, N.X);
  Gravity := FXDirection(S.GravityAngle);
  Fade := EnsureRange(1 - T / Max(0.05, Life), 0.0, 1.0);
  V := Default(TFXVisual);
  V.Shape := S.Shape; V.Color := P.Color; V.Size := P.Size;
  V.Aspect := S.Aspect; V.Angle := P.Phase + DegToRad(P.Spin * Age);
  V.Opacity := S.Opacity * Fade;
  V.Position := FXVec(State.HitPosition.X + N.X * 0.7, State.HitPosition.Y + N.Y * 0.7);
  V.IsSplash := True;
  if Response in [1, 5] then
  begin
    Dot := FXDot(State.HitVelocity, N);
    Reflected := FXVec((State.HitVelocity.X - 2 * Dot * N.X) * S.Bounce,
      (State.HitVelocity.Y - 2 * Dot * N.Y) * S.Bounce);
    if Response = 5 then
    begin
      Dot := FXDot(Gravity, Tangent) * S.Slide * 80;
      // 輪郭の外への位置補正は済んでいる。外向きの初速を足すと上面から浮き上がる。
      Reflected := FXVec(Tangent.X * Dot, Tangent.Y * Dot);
    end;
    if (T <= Life) and Flight(V.Position, Reflected, P.Size * 0.65, True,
      V.Position, V.Velocity) then Output.Add(V);
    Exit;
  end;
  if Response = 2 then
  begin
    V.Position.X := V.Position.X + Tangent.X * FXDot(Gravity, Tangent) * S.Slide * T * 18;
    V.Position.Y := V.Position.Y + Tangent.Y * FXDot(Gravity, Tangent) * S.Slide * T * 18;
    V.Size := V.Size * (1 + T * 0.3);
    if T <= Life then Output.Add(V);
    Exit;
  end;
  if (Response = 4) and (T <= Life) then
  begin
    Count := Min(12, Round(S.Splash * 7));
    ImpactScale := 1;
    // A direct jet impact throws droplets farther than a glancing hit.
    if (S.Style = fsWater) and (S.Emission = feSpray) then
      ImpactScale := EnsureRange(-FXDot(State.HitVelocity, N) / 700, 1.0, 2.0);
    for I := 0 to Count - 1 do
    begin
      // 飛散は接触面の外向き半球へ出す。側面・下面の接触も同じ式で扱う。
      Angle := (FXRandom(P.ID, S.Seed, 100 + Cardinal(I)) - 0.5) * Pi * 0.95;
      Direction := FXVec(N.X * Cos(Angle) + Tangent.X * Sin(Angle),
        N.Y * Cos(Angle) + Tangent.Y * Sin(Angle));
      Speed := S.SplashSpeed * (0.5 + FXRandom(P.ID, S.Seed, 130 + Cardinal(I)));
      V.Size := Max(0.55, P.Size * 0.48);
      if ImpactScale > 1 then
      begin
        Speed := Speed * ImpactScale;
        V.Size := Max(0.55, P.Size * (0.32 + 0.28 * FXRandom(P.ID, S.Seed, 220 + Cardinal(I))));
      end;
      V.Opacity := S.Opacity * Fade * 0.8;
      if S.Style = fsSpark then V.Shape := shLight else V.Shape := shDrop;
      if Flight(FXVec(State.HitPosition.X + N.X * 1.5, State.HitPosition.Y + N.Y * 1.5),
        FXVec(Direction.X * Speed, Direction.Y * Speed), V.Size * 0.65, False,
        V.Position, V.Velocity) then Output.Add(V);
    end;
  end;
end;

procedure TFXSimulator.RenderParticle(const P: TFXParticle; Age: Double;
  const S: TFXSettings; Environment: TFXEnvironment; Output: TFXVisualList);
var
  State, RenderState: TFXCacheEntry;
  FullSteps: Integer;
  Tail, Fade: Double;
  V: TFXVisual;
begin
  if (Age < 0) or (Age > P.Life) then Exit;
  FullSteps := Floor(Age / SIM_DT + 1E-9);
  if not FCache.TryGetValue(P.ID, State) or (State.Step > FullSteps) then
  begin
    State := Default(TFXCacheEntry);
    State.Position := P.Position; State.Velocity := P.Velocity;
  end;
  while (State.Step < FullSteps) and not State.Hit do
  begin
    Advance(State, P, S, Environment, State.Step * SIM_DT, SIM_DT);
    Inc(State.Step);
  end;
  // 接触後も整数刻みの時点を記録する。判定そのものは最初の一度だけ保持する。
  State.Step := FullSteps;
  FCache.AddOrSetValue(P.ID, State);
  RenderState := State;
  Tail := Max(0.0, Age - FullSteps * SIM_DT);
  if not RenderState.Hit then Advance(RenderState, P, S, Environment, FullSteps * SIM_DT, Tail);
  if RenderState.Hit then
  begin
    ContactVisuals(P, RenderState, Age, S, Environment, Output);
    Exit;
  end;
  if (RenderState.Position.X < -P.Size * 10) or
    (RenderState.Position.Y < -P.Size * 10) or
    (RenderState.Position.X > Environment.Width + P.Size * 10) or
    (RenderState.Position.Y > Environment.Height + P.Size * 10) then Exit;
  Fade := Min(1.0, (P.Life - Age) / Min(0.5, P.Life * 0.15));
  V := Default(TFXVisual);
  V.Position := RenderState.Position; V.Velocity := RenderState.Velocity;
  V.Size := P.Size; V.Angle := P.Phase + DegToRad(P.Spin * Age);
  if S.GlideStrength > 0 then V.Angle := RenderState.Glide.Angle;
  V.Opacity := S.Opacity * Fade * Min(1.0, Age / 0.04);
  V.Aspect := S.Aspect; V.Color := P.Color; V.Shape := S.Shape;
  Output.Add(V);
end;

procedure TFXSimulator.Generate(Time: Double; const Settings: TFXSettings;
  Environment: TFXEnvironment; Output: TFXVisualList);
var
  I, First, Last, Cycle, FirstCycle, LastCycle, ID, Stride: Int64;
  Birth, Earliest, Rate, Lifetime, ParticleLifetime, Phase, Age: Double;
  Timing: TFXStartupTiming;
  Count, Issued: Integer;
  P: TFXParticle;
begin
  Output.Clear; FSimulatedSteps := 0; FCollisionCount := 0;
  if not FPrepared or (FRevision <> Environment.Revision) or
    not CompareMem(@FSettings, @Settings, SizeOf(Settings)) then
  begin
    FCache.Clear; FSettings := Settings; FRevision := Environment.Revision; FPrepared := True;
  end;
  if FCache.Count > FX_MAX_PARTICLES * 2 then FCache.Clear;
  if (Settings.Opacity <= 0) or (Settings.Rate <= 0) then Exit;
  Time := Time + Settings.Offset;
  Timing := FXStartupTiming(Settings, Environment.Width, Environment.Height);
  ParticleLifetime := Timing.ParticleLifetime;
  Lifetime := ParticleLifetime * 1.16;
  Issued := 0;
  if Settings.Emission in [feShot, feExplosion] then
  begin
    if Time < Settings.StartTime then Exit;
    Count := EnsureRange(Round(Settings.Burst), 0, FX_MAX_PARTICLES);
    FirstCycle := 0; LastCycle := 0;
    if Settings.Period > 0 then
    begin
      FirstCycle := Max(Int64(0), Ceil((Time - Settings.StartTime - Lifetime) / Settings.Period));
      LastCycle := Floor((Time - Settings.StartTime) / Settings.Period);
    end;
    for Cycle := FirstCycle to LastCycle do
    begin
      Birth := Settings.StartTime + Cycle * Settings.Period;
      for I := 0 to Count - 1 do
      begin
        if Issued >= FX_MAX_PARTICLES then Exit;
        ID := Cycle * FX_MAX_PARTICLES + I;
        P := NewParticle(ID, Birth, ParticleLifetime, Settings, Environment.Width, Environment.SourceHeight);
        RenderParticle(P, Time - Birth, Settings, Environment, Output);
        Inc(Issued);
      end;
    end;
    Exit;
  end;
  Rate := Settings.Rate;
  if (Settings.StartTime > 0) and (Time < Settings.StartTime) then Exit;
  Earliest := Settings.StartTime - Timing.Prewarm;
  if Time < Earliest then Exit;
  First := Floor((Max(Earliest, Time - Lifetime) - Settings.StartTime) * Rate) - 1;
  Last := Floor((Time - Settings.StartTime) * Rate);
  Stride := Max(Int64(1), Ceil(Rate * Lifetime / FX_MAX_PARTICLES));
  for I := First to Last do
  begin
    if (I mod Stride) <> 0 then Continue;
    Birth := Settings.StartTime + (I + FXRandom(I, Settings.Seed, 20) * 0.9) / Rate;
    if (Birth < Earliest) or (Birth > Time) then Continue;
    if Settings.Duration > 0 then
    begin
      Phase := Birth - Settings.StartTime;
      if Settings.Period > 0 then Phase := Phase - Floor(Phase / Settings.Period) * Settings.Period;
      if Phase > Settings.Duration then Continue;
    end;
    Age := Time - Birth;
    if (Age < 0) or (Age > Lifetime) then Continue;
    P := NewParticle(I, Birth, ParticleLifetime, Settings, Environment.Width, Environment.SourceHeight);
    RenderParticle(P, Age, Settings, Environment, Output);
    Inc(Issued);
    if Issued >= FX_MAX_PARTICLES then Break;
  end;
end;

end.
