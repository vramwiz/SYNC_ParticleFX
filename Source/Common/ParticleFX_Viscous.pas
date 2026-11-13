unit ParticleFX_Viscous;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 粘性粒子の近傍相互作用、輪郭に沿う移動、前面への滴下を固定刻みで計算する。
// 画像は2Dの接触面として扱う。凹部の滞留は有限とし、前面を通って流出させる。
// キャッシュは固定時刻の全粒子を所有し、逆シークでも同じ起点から再現する。

interface

uses
  System.Generics.Collections, ParticleFX_Types, ParticleFX_Collision,
  ParticleFX_Simulation;

const
  FX_MAX_VISCOUS_PARTICLES = 2048;

type
  TFXFlowPhase = (fpAir, fpSurface, fpFront, fpFloor);
  TFXFlowParticle = record
    Particle: TFXParticle;
    Position, Velocity, Normal: TFXVec;
    Phase: TFXFlowPhase;
    ContactTime, FrontTime: Double;
    Contact, EnteredImage: Boolean;
  end;
  TFXFlowSnapshot = record
    Tick: Integer;
    Particles: TArray<TFXFlowParticle>;
  end;

  TFXViscousFlow = class
  private
    FFactory: TFXSimulator; // 借用。共通の初期粒子生成だけを利用する。
    FParticles: TArray<TFXFlowParticle>;
    FVelocity: TArray<TFXVec>;
    FHeads, FNext: TArray<Integer>;
    FCheckpoints: TList<TFXFlowSnapshot>;
    FSettings: TFXSettings;
    FCount, FTick, FRevision, FSteps, FContacts: Integer;
    FPrepared, FAllowPrestart: Boolean;
    procedure Reset(const S: TFXSettings; Environment: TFXEnvironment);
    procedure SaveCheckpoint;
    procedure Restore(TimeTick: Integer);
    procedure Spawn(A, B: Double; const S: TFXSettings; Environment: TFXEnvironment);
    procedure Advance(A, B: Double; const S: TFXSettings; Environment: TFXEnvironment);
    procedure Visuals(Time: Double; const S: TFXSettings; Output: TFXVisualList);
  public
    constructor Create(Factory: TFXSimulator);
    destructor Destroy; override;
    // Outputを置き換える。FactoryとEnvironmentを所有せず、入力マスクは変更しない。
    procedure Generate(Time: Double; const S: TFXSettings;
      Environment: TFXEnvironment; Output: TFXVisualList);
    // 現在の固定刻みの状態を複製する。呼出側の変更は計算履歴へ影響しない。
    function SnapshotParticles: TArray<TFXFlowParticle>;
    property SimulatedSteps: Integer read FSteps;
    property Contacts: Integer read FContacts;
  end;

implementation

uses
  System.Math, System.SysUtils;

const
  FLOW_DT = 1.0 / 60;

constructor TFXViscousFlow.Create(Factory: TFXSimulator);
begin
  inherited Create;
  FFactory := Factory;
  SetLength(FParticles, FX_MAX_VISCOUS_PARTICLES);
  SetLength(FVelocity, FX_MAX_VISCOUS_PARTICLES);
  SetLength(FNext, FX_MAX_VISCOUS_PARTICLES);
  FCheckpoints := TList<TFXFlowSnapshot>.Create;
end;

destructor TFXViscousFlow.Destroy;
begin
  FCheckpoints.Free;
  inherited;
end;

function TFXViscousFlow.SnapshotParticles: TArray<TFXFlowParticle>;
begin
  Result := Copy(FParticles, 0, FCount);
end;

procedure TFXViscousFlow.SaveCheckpoint;
var
  Snapshot: TFXFlowSnapshot;
begin
  Snapshot.Tick := FTick;
  Snapshot.Particles := Copy(FParticles, 0, FCount);
  FCheckpoints.Add(Snapshot);
  // 最初の起点は残し、2秒間隔の履歴を最大16個保持する。
  if FCheckpoints.Count > 17 then FCheckpoints.Delete(1);
end;

procedure TFXViscousFlow.Reset(const S: TFXSettings; Environment: TFXEnvironment);
var
  Timing: TFXStartupTiming;
begin
  FSettings := S; FRevision := Environment.Revision; FCount := 0;
  Timing := FXStartupTiming(S, Environment.Width, Environment.Height);
  FAllowPrestart := (S.Emission = feContinuous) and (Timing.Prewarm > 0);
  FTick := Floor((S.StartTime - Timing.Prewarm) / FLOW_DT);
  FCheckpoints.Clear; SaveCheckpoint; FPrepared := True;
end;

procedure TFXViscousFlow.Restore(TimeTick: Integer);
var
  I: Integer;
  Best: TFXFlowSnapshot;
begin
  Best := FCheckpoints[0];
  for I := 1 to FCheckpoints.Count - 1 do
    if (FCheckpoints[I].Tick <= TimeTick) and (FCheckpoints[I].Tick > Best.Tick) then
      Best := FCheckpoints[I];
  FTick := Best.Tick; FCount := Length(Best.Particles);
  if FCount > 0 then Move(Best.Particles[0], FParticles[0], FCount * SizeOf(TFXFlowParticle));
  // 先の履歴を捨て、同じ時刻のスナップショットを重複保持しない。
  for I := FCheckpoints.Count - 1 downto 1 do
    if FCheckpoints[I].Tick > FTick then FCheckpoints.Delete(I);
end;

procedure TFXViscousFlow.Spawn(A, B: Double; const S: TFXSettings; Environment: TFXEnvironment);
var
  I, First, Last, Cycle: Int64;
  Birth, Phase: Double;
  Count: Integer;
  procedure Add(ID: Int64; Birth: Double);
  var
    P: TFXFlowParticle;
  begin
    if (Birth < A - 1E-9) or (Birth >= B - 1E-9) or
      (FCount >= FX_MAX_VISCOUS_PARTICLES) then Exit;
    P := Default(TFXFlowParticle);
    P.Particle := FFactory.NewParticle(ID, Birth, S.Lifetime, S,
      Environment.Width, Environment.SourceHeight);
    P.Position := P.Particle.Position; P.Velocity := P.Particle.Velocity;
    FParticles[FCount] := P; Inc(FCount);
  end;
begin
  if (S.Rate <= 0) or (B <= S.StartTime) and (S.Emission <> feContinuous) then Exit;
  if S.Emission in [feShot, feExplosion] then
  begin
    First := 0; Last := 0;
    if S.Period > 0 then
    begin
      First := Max(Int64(0), Floor((A - S.StartTime) / S.Period));
      Last := Max(Int64(0), Floor((B - S.StartTime) / S.Period));
    end;
    Count := EnsureRange(Round(S.Burst), 0, FX_MAX_VISCOUS_PARTICLES);
    for Cycle := First to Last do
    begin
      Birth := S.StartTime + Cycle * S.Period;
      for I := 0 to Count - 1 do Add(Cycle * FX_MAX_PARTICLES + I, Birth);
    end;
  end else begin
    First := Floor((A - S.StartTime) * S.Rate) - 1;
    Last := Floor((B - S.StartTime) * S.Rate);
    for I := First to Last do
    begin
      Birth := S.StartTime + (I + FXRandom(I, S.Seed, 20) * 0.9) / S.Rate;
      if (Birth < S.StartTime) and not FAllowPrestart then Continue;
      Phase := Birth - S.StartTime;
      if S.Period > 0 then Phase := Phase - Floor(Phase / S.Period) * S.Period;
      if (S.Duration > 0) and (Phase > S.Duration) then Continue;
      Add(I, Birth);
    end;
  end;
end;

procedure TFXViscousFlow.Advance(A, B: Double; const S: TFXSettings; Environment: TFXEnvironment);
var
  I, J, K, X, Y, CX, CY, GW, GH, CellIndex: Integer;
  Cell, Radius, Dist, Weight, Sum, Desired, Force, DT, Speed, Dot, Fraction,
    Hold, Amount, Gust, Wave, Blend: Double;
  G, Wind, Delta, Mean, Pull, V, Next, Hit, N, Tangent, Accel, Supported: TFXVec;
  P: TFXFlowParticle;
begin
  K := 0;
  for I := 0 to FCount - 1 do
    if B - FParticles[I].Particle.Birth <= FParticles[I].Particle.Life then
    begin FParticles[K] := FParticles[I]; Inc(K); end;
  FCount := K;
  Spawn(A, B, S, Environment);
  Cell := Max(8.0, S.Size * 4); Radius := Cell;
  GW := Ceil(Environment.Width / Cell) + 6; GH := Ceil(Environment.Height / Cell) + 6;
  SetLength(FHeads, GW * GH);
  FillChar(FHeads[0], Length(FHeads) * SizeOf(Integer), $FF);
  for I := 0 to FCount - 1 do
  begin
    X := EnsureRange(Floor(FParticles[I].Position.X / Cell) + 3, 0, GW - 1);
    Y := EnsureRange(Floor(FParticles[I].Position.Y / Cell) + 3, 0, GH - 1);
    CellIndex := Y * GW + X; FNext[I] := FHeads[CellIndex]; FHeads[CellIndex] := I;
  end;
  G := FXDirection(S.GravityAngle); Wind := FXDirection(S.WindAngle);
  Gust := S.Gust * (Sin(B * 2 * Pi / S.GustPeriod) * 0.65 +
    Sin(B * 2 * Pi / (S.GustPeriod * 1.713) + 1.7) * 0.35);
  // 全粒子の旧状態から近傍速度を求め、更新順による結果の違いを防ぐ。
  for I := 0 to FCount - 1 do
  begin
    P := FParticles[I]; DT := Max(0.0, B - Max(A, P.Particle.Birth));
    Mean := FXVec(0, 0); Pull := FXVec(0, 0); Sum := 0;
    CX := EnsureRange(Floor(P.Position.X / Cell) + 3, 0, GW - 1);
    CY := EnsureRange(Floor(P.Position.Y / Cell) + 3, 0, GH - 1);
    for Y := Max(0, CY - 1) to Min(GH - 1, CY + 1) do
      for X := Max(0, CX - 1) to Min(GW - 1, CX + 1) do
      begin
        J := FHeads[Y * GW + X];
        while J >= 0 do
        begin
          if J <> I then
          begin
            Delta := FXVec(FParticles[J].Position.X - P.Position.X, FParticles[J].Position.Y - P.Position.Y);
            Dist := FXLength(Delta);
            if (Dist > 0.01) and (Dist < Radius) then
            begin
              Weight := Sqr(1 - Dist / Radius); Sum := Sum + Weight;
              Mean.X := Mean.X + FParticles[J].Velocity.X * Weight;
              Mean.Y := Mean.Y + FParticles[J].Velocity.Y * Weight;
              Desired := (P.Particle.Size + FParticles[J].Particle.Size) * 0.8;
              Force := (Dist - Desired) * Weight * S.Cohesion * 45;
              if Dist < Desired then Force := (Dist - Desired) * Weight * 120;
              Pull.X := Pull.X + Delta.X / Dist * Force;
              Pull.Y := Pull.Y + Delta.Y / Dist * Force;
            end;
          end;
          J := FNext[J];
        end;
      end;
    V := P.Velocity;
    if Sum > 0 then
    begin
      Blend := 1 - Exp(-S.Viscosity * DT * 12 * Min(3.0, Sum));
      V.X := V.X + (Mean.X / Sum - V.X) * Blend + Pull.X * DT;
      V.Y := V.Y + (Mean.Y / Sum - V.Y) * Blend + Pull.Y * DT;
    end;
    Accel := FXVec(G.X * S.Gravity + Wind.X * (S.Wind + Gust),
      G.Y * S.Gravity + Wind.Y * (S.Wind + Gust));
    Wave := B * 2 * Pi / S.TurbulencePeriod + P.Particle.Phase;
    Accel.X := Accel.X + S.Turbulence * Sin(Wave);
    Accel.Y := Accel.Y + S.Turbulence * Cos(Wave * 0.83);
    V := FXVec((V.X + Accel.X * DT) * Exp(-S.Drag * DT),
      (V.Y + Accel.Y * DT) * Exp(-S.Drag * DT));
    if S.Vortex <> 0 then
    begin
      Wave := DegToRad(S.Vortex) * DT;
      V := FXVec(V.X * Cos(Wave) - V.Y * Sin(Wave), V.X * Sin(Wave) + V.Y * Cos(Wave));
    end;
    Speed := FXLength(V);
    if Speed > S.MaxSpeed then V := FXVec(V.X * S.MaxSpeed / Speed, V.Y * S.MaxSpeed / Speed);
    FVelocity[I] := V;
  end;
  Amount := 0;
  if S.Accumulation then Amount := EnsureRange(S.AccumAmount - Max(0.0, B) * S.Melt, 0.0, 100.0) / 100;
  Hold := Max(0.08, S.DripTime * (0.2 + S.Viscosity * 0.8) *
    (0.2 + Amount * 0.8) * (0.25 + S.Adhesion * 0.75));
  for I := 0 to FCount - 1 do
  begin
    P := FParticles[I]; DT := Max(0.0, B - Max(A, P.Particle.Birth));
    P.Velocity := FVelocity[I];
    if P.Phase = fpSurface then
    begin
      Tangent := FXVec(-P.Normal.Y, P.Normal.X);
      Dot := FXDot(P.Velocity, Tangent) * Exp(-(S.Viscosity * 5 + (1 - S.Slide) * 2) * DT);
      P.Velocity := FXVec(Tangent.X * Dot, Tangent.Y * Dot);
      Next := FXVec(P.Position.X + P.Velocity.X * DT, P.Position.Y + P.Velocity.Y * DT);
      Radius := Max(2.0, P.Particle.Size * 1.3);
      if (S.Gravity > 0) and ((B - P.ContactTime >= Hold) or (S.Adhesion <= 0)) then
      begin
        P.Phase := fpFront; P.FrontTime := B; P.EnteredImage := False;
        Speed := 12 + (1 - S.Viscosity) * 30;
        P.Velocity := FXVec(P.Velocity.X + G.X * Speed, P.Velocity.Y + G.Y * Speed);
      end else if Environment.Trace(
        FXVec(Next.X + P.Normal.X * Radius, Next.Y + P.Normal.Y * Radius),
        FXVec(Next.X - P.Normal.X * Radius, Next.Y - P.Normal.Y * Radius),
        P.Particle.Size * 0.65, Hit, N, Fraction, True) then
      begin
        Supported := FXVec(Hit.X + N.X * 0.6, Hit.Y + N.Y * 0.6);
        // 別の面や内側へ飛ぶ補正を採用せず、その場から自由落下へ戻す。
        if (FXDot(N, P.Normal) >= 0) and not Environment.ContainsImage(Supported) and
          (FXLength(FXVec(Supported.X - Next.X, Supported.Y - Next.Y)) <= Max(1.5, P.Particle.Size * 0.35)) then
        begin P.Position := Supported; P.Normal := N; end
        else begin P.Phase := fpAir; P.Position := Next; end;
      end else begin P.Phase := fpAir; P.Position := Next; end;
    end else begin
      Next := FXVec(P.Position.X + P.Velocity.X * DT, P.Position.Y + P.Velocity.Y * DT);
      if (P.Phase = fpAir) and S.Collision and
        Environment.Trace(P.Position, Next, P.Particle.Size * 0.65, Hit, N, Fraction, True) then
      begin
        P.Position := FXVec(Hit.X + N.X * 0.7, Hit.Y + N.Y * 0.7);
        P.Normal := N; P.Phase := fpSurface; P.Contact := True; P.ContactTime := B;
        if S.Response = 1 then
        begin
          Dot := FXDot(P.Velocity, N);
          P.Velocity := FXVec((P.Velocity.X - 2 * Dot * N.X) * S.Bounce,
            (P.Velocity.Y - 2 * Dot * N.Y) * S.Bounce);
          P.Phase := fpAir;
        end else if S.Response = 3 then P.Particle.Life := 0;
        Inc(FContacts);
      end else P.Position := Next;
      if P.Phase = fpFront then
      begin
        if Environment.ContainsImage(P.Position) then P.EnteredImage := True
        else if (B - P.FrontTime > 0.15) and P.EnteredImage then P.Phase := fpAir;
      end;
    end;
    // 床は画像の前面流とは別に判定し、床位置を下余白で移動させない。
    if S.Collision and S.FloorEnabled and (P.Position.Y >= Environment.FloorY - P.Particle.Size) and
      (P.Velocity.Y >= 0) then
    begin
      P.Position.Y := Environment.FloorY - P.Particle.Size;
      P.Velocity.Y := 0; P.Phase := fpFloor; P.Contact := True;
    end;
    Speed := FXLength(P.Velocity);
    if Speed > S.MaxSpeed then
      P.Velocity := FXVec(P.Velocity.X * S.MaxSpeed / Speed, P.Velocity.Y * S.MaxSpeed / Speed);
    FParticles[I] := P;
  end;
  Inc(FSteps, FCount);
end;

procedure TFXViscousFlow.Visuals(Time: Double; const S: TFXSettings; Output: TFXVisualList);
var
  I: Integer;
  P: TFXFlowParticle;
  V: TFXVisual;
  Age, Scale, Amount: Double;
begin
  Amount := 0;
  if S.Accumulation then Amount := EnsureRange(S.AccumAmount - Max(0.0, Time) * S.Melt, 0.0, 100.0) / 100;
  for I := 0 to FCount - 1 do
  begin
    P := FParticles[I]; Age := Time - P.Particle.Birth;
    if (Age < 0) or (Age > P.Particle.Life) then Continue;
    V := Default(TFXVisual); V.Position := P.Position; V.Velocity := P.Velocity;
    V.Shape := shSlime; V.Color := P.Particle.Color; V.Size := P.Particle.Size;
    V.IsSplash := P.Contact;
    V.Opacity := S.Opacity * Min(1.0, Age / 0.04) * Min(1.0, (P.Particle.Life - Age) / 0.5);
    V.Aspect := S.Aspect * (1 + Min(1.8, FXLength(P.Velocity) * 0.004 * S.Viscosity));
    V.Angle := ArcTan2(P.Velocity.Y, P.Velocity.X) - Pi / 2;
    if P.Phase in [fpSurface, fpFloor] then
    begin
      Scale := 0.65 + Amount * Min(1.6, S.MaxThickness / Max(1.0, P.Particle.Size) * 0.3);
      V.Size := V.Size * Scale;
      if Amount > 0 then
      begin
        V.Opacity := V.Opacity * S.AccumOpacity;
        if S.CustomAccumColor then V.Color := S.AccumColor;
      end;
    end;
    Output.Add(V);
  end;
end;

procedure TFXViscousFlow.Generate(Time: Double; const S: TFXSettings;
  Environment: TFXEnvironment; Output: TFXVisualList);
var
  Target: Integer;
  Tail: Double;
  Saved: TArray<TFXFlowParticle>;
begin
  Output.Clear; FSteps := 0; FContacts := 0;
  Time := Time + S.Offset;
  if not FPrepared or (FRevision <> Environment.Revision) or
    not CompareMem(@FSettings, @S, SizeOf(S)) then Reset(S, Environment);
  if (S.StartTime > 0) and (Time < S.StartTime) then
  begin
    if FTick > FCheckpoints[0].Tick then Restore(FCheckpoints[0].Tick);
    Exit;
  end;
  Target := Floor(Time / FLOW_DT + 1E-9);
  if (Target < FCheckpoints[0].Tick) or (S.Opacity <= 0) then Exit;
  if Target < FTick then Restore(Target);
  while FTick < Target do
  begin
    Advance(FTick * FLOW_DT, (FTick + 1) * FLOW_DT, S, Environment);
    Inc(FTick);
    if FTick mod 120 = 0 then SaveCheckpoint;
  end;
  Tail := Max(0.0, Time - FTick * FLOW_DT);
  if Tail > 1E-9 then
  begin
    Saved := Copy(FParticles, 0, FCount);
    Advance(FTick * FLOW_DT, Time, S, Environment);
    Visuals(Time, S, Output);
    FCount := Length(Saved);
    if FCount > 0 then Move(Saved[0], FParticles[0], FCount * SizeOf(TFXFlowParticle));
  end else Visuals(Time, S, Output);
end;

end.
