unit ParticleFX_Motion;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 重力で得た速度を揚力で曲げ、滑空・浮上・失速を繰り返して落下させる。
// 揚力は速度の向きを変えるだけで速さを増やさない。失速では運動エネルギーを失う。
// 状態は粒子ごとに所有し、方向の選び直しだけを番号・シード・失速回数で決める。

interface

uses ParticleFX_Types;

type
  TFXGlideState = record
    Direction, Cycle: Integer;
    Climbed, Stalled: Boolean;
    RadiusFactor, Angle: Double;
  end;

// 呼出側が重力・風・抵抗を加えた後のVelocityへ、揚力による旋回を適用する。
// Stateは同じ粒子の固定刻みの履歴へ保存する。速度を増やす推進力は与えない。
procedure FXTurnGlide(ID: Int64; Depth, DT: Double; const S: TFXSettings;
  var State: TFXGlideState; var Velocity: TFXVec);

implementation

uses System.Math;

procedure FXTurnGlide(ID: Int64; Depth, DT: Double; const S: TFXSettings;
  var State: TFXGlideState; var Velocity: TFXVec);
var
  G, Tangent: TFXVec;
  Along, Down, Speed, Stall, Radius, Turn, CS, SN, X, Y, TargetAngle, Delta: Double;
begin
  if (S.GlideStrength <= 0) or (DT <= 0) then Exit;
  G := FXDirection(S.GravityAngle); Tangent := FXVec(G.Y, -G.X);
  Along := FXDot(Velocity, Tangent); Down := FXDot(Velocity, G);
  Speed := FXLength(Velocity);
  Stall := Max(1.0, S.StallSpeed * Sqrt(Max(0.1, Depth)));
  if State.Direction = 0 then
  begin
    State.Direction := 1;
    if Abs(Along) > Speed * 0.1 then
    begin
      if Along < 0 then State.Direction := -1;
    end else if FXRandom(ID, S.Seed, 71) < 0.5 then State.Direction := -1;
    State.RadiusFactor := 0.85 + FXRandom(ID, S.Seed, 72) * 0.3;
    State.Angle := ArcTan2(Velocity.Y, Velocity.X) + Pi / 2;
  end;
  if not State.Stalled and (Down < -Stall * 0.2) then State.Climbed := True;
  if not State.Stalled and State.Climbed and
    ((Speed < Stall) or (Down >= -Stall * 0.15)) then
  begin
    State.Stalled := True; State.Climbed := False;
    Inc(State.Cycle);
    // 次の弧は同じ向き、または逆向き。低速になった頂点でだけ選び直す。
    if FXRandom(ID, S.Seed, 80 + Cardinal(State.Cycle)) < 0.5 then
      State.Direction := -State.Direction;
    State.RadiusFactor := 0.85 + FXRandom(ID, S.Seed, 180 + Cardinal(State.Cycle)) * 0.3;
    Along := Along * 0.35; Down := Down * 0.35;
    Speed := Speed * 0.35;
  end;
  if State.Stalled and (Down > Stall * 0.65) then
  begin
    State.Stalled := False;
    Along := State.Direction * Abs(Along);
  end;
  if not State.Stalled then
  begin
    Radius := Max(10.0, S.GlideRadius * Max(0.2, Depth) * State.RadiusFactor);
    Turn := -State.Direction * Min(6.0, S.GlideStrength * Speed / Radius) * DT;
    CS := Cos(Turn); SN := Sin(Turn);
    X := Along * CS - Down * SN; Y := Along * SN + Down * CS;
    Along := X; Down := Y;
  end;
  Velocity := FXVec(Tangent.X * Along + G.X * Down, Tangent.Y * Along + G.Y * Down);
  TargetAngle := ArcTan2(Velocity.Y, Velocity.X) + Pi / 2;
  if State.Stalled then
    TargetAngle := ArcTan2(Tangent.Y * State.Direction + G.Y * 0.5,
      Tangent.X * State.Direction + G.X * 0.5) + Pi / 2;
  Delta := ArcTan2(Sin(TargetAngle - State.Angle), Cos(TargetAngle - State.Angle));
  State.Angle := State.Angle + EnsureRange(Delta, -5 * DT, 5 * DT);
end;

end.
