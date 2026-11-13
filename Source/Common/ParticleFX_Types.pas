unit ParticleFX_Types;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// スタイル、発生方式、描画設定と決定的な乱数を定義する。
// ホストや描画APIに依存せず、描画処理と実験用プロジェクトで共用する。

interface

uses
  System.Math;

const
  FX_MAX_PARTICLES = 12000;
  FX_MAX_PIXELS = 16777216;
  FX_STYLE_COUNT = 12;
  FX_PRESET_COUNT = 23;

type
  TFXStyle = (fsRain, fsSnow, fsWater, fsPetal, fsLeaf, fsConfetti,
    fsSand, fsHail, fsFountain, fsSpark, fsInk, fsSlime);
  TFXEmission = (feContinuous, feShot, feExplosion, feJet);
  TFXShape = (shDrop, shSnow, shPetal, shLeaf, shPaper, shGrain,
    shHail, shLight, shInk, shSlime);
  TFXVec = record
    X, Y: Double;
  end;
  // ストレートRGBA。ホストSDKから独立した4バイトの画素表現。
  TFXPixelRGBA = packed record
    R, G, B, A: Byte;
  end;
  TFXPixels = TArray<TFXPixelRGBA>;

  TFXProfile = record
    Emission: TFXEmission;
    Shape: TFXShape;
    Rate, Speed, Size, Gravity, Life, Sway, Drag, BaseAngle: Double;
    Color: Cardinal;
  end;

  TFXSettings = record
    Style: TFXStyle;
    Emission: TFXEmission;
    Shape: TFXShape;
    Seed: Cardinal;
    Rate, Speed, Size, SizeVariation, SpeedVariation: Double;
    Angle, DirectionSpread, GravityAngle, Gravity: Double;
    WindAngle, Wind, Gust, GustPeriod, Turbulence, TurbulencePeriod: Double;
    Vortex, Drag, MaxSpeed, Sway, SwaySpeed, Rotation: Double;
    EmitterX, EmitterY, EmitterRange, StartTime, Duration, Period, Lifetime: Double;
    Offset, Prewarm, Burst, Opacity, ColorVariation, Aspect: Double;
    Color, AccumColor: Cardinal;
    CustomColor, CustomAccumColor, Collision, Accumulation, FloorEnabled: Boolean;
    AutomaticLifetime, AutomaticEmitter: Boolean;
    AlphaThreshold, Response, AccumShape: Integer;
    Bounce, Splash, SplashSpeed, ContactLife, Slide: Double;
    AccumAmount, MaxThickness, Roughness, MaxSlope, AccumOpacity: Double;
    Melt, FloorPosition, Blur, MotionBlur, Glow, Depth: Double;
    CanvasWidth, CanvasHeight, DrawMode: Integer;
    Viscosity, Cohesion, Adhesion, DripTime: Double;
    BottomMargin: Integer;
    InitialState: Double;
  end;

  TFXStartupTiming = record
    ParticleLifetime, FullPrewarm, Prewarm, RampTime: Double;
  end;

  TFXVisual = record
    Position, Velocity: TFXVec;
    Size, Angle, Opacity, Aspect: Single;
    Color: Cardinal;
    Shape: TFXShape;
    IsSplash: Boolean;
  end;

  TFXVisualList = class
  private
    FItems: TArray<TFXVisual>;
    FCount: Integer;
    function GetItem(Index: Integer): TFXVisual;
  public
    // 格納領域を再利用して現在フレームの要素数だけをリセットする。
    procedure Clear;
    // 値を複製して登録する。飛散を含む描画数にも上限を設ける。
    procedure Add(const Value: TFXVisual);
    property Count: Integer read FCount;
    property Items[Index: Integer]: TFXVisual read GetItem; default;
  end;

// 角度0は下、90は右。スタイル既定方向との加算は設定側で行う。
function FXDirection(Degrees: Double): TFXVec;
function FXVec(X, Y: Double): TFXVec; inline;
function FXLength(const V: TFXVec): Double; inline;
function FXDot(const A, B: TFXVec): Double; inline;
function FXNormalize(const V: TFXVec): TFXVec;
// 入力番号とシードのみから0以上1未満を返す。グローバル乱数を変更しない。
function FXRandom(Index: Int64; Seed, Channel: Cardinal): Double;
function FXNoise(Position: Double; Seed: Cardinal): Double;
function FXProfile(Style: TFXStyle): TFXProfile;
function FXDefaultSettings(Style: TFXStyle): TFXSettings;
// 速度・重力・画像サイズから予備動作を求め、開始状態の割合を適用する。
// 時間補正や風の時刻を変更せず、発生時刻より前の計算量だけを返す。
function FXStartupTiming(const S: TFXSettings; Width, Height: Integer): TFXStartupTiming;
// 静的な蓄積の開始進行。100では従来の蓄積量をそのまま使用する。
function FXStartupAccumulation(Time: Double; const S: TFXSettings; Width, Height: Integer): Double;
// 素材固有のプリセットはスタイルも切り替え、基準値を返す。外部の値は変更しない。
function FXPresetSettings(Style: TFXStyle; Preset: Integer): TFXSettings;
function FXStyleName(Style: TFXStyle): string;
function FXParticleColor(const S: TFXSettings; Index: Int64): Cardinal;

implementation

function FXVec(X, Y: Double): TFXVec;
begin
  Result.X := X;
  Result.Y := Y;
end;

function FXDirection(Degrees: Double): TFXVec;
begin
  Result.X := Sin(DegToRad(Degrees));
  Result.Y := Cos(DegToRad(Degrees));
end;

function FXLength(const V: TFXVec): Double;
begin
  Result := Sqrt(Sqr(V.X) + Sqr(V.Y));
end;

function FXDot(const A, B: TFXVec): Double;
begin
  Result := A.X * B.X + A.Y * B.Y;
end;

function FXNormalize(const V: TFXVec): TFXVec;
var
  L: Double;
begin
  L := FXLength(V);
  if L < 1E-9 then Exit(FXVec(0, -1));
  Result := FXVec(V.X / L, V.Y / L);
end;

{$IFOPT Q+}{$DEFINE FX_RESTORE_OVERFLOW}{$ENDIF}
{$IFOPT R+}{$DEFINE FX_RESTORE_RANGE}{$ENDIF}
{$Q-}
{$R-}
function FXRandom(Index: Int64; Seed, Channel: Cardinal): Double;
var
  V: Cardinal;
begin
  // ハッシュの折り返しだけを明示的に許可し、Debugの範囲検証を他へ残す。
  V := Cardinal(Index) xor Cardinal(UInt64(Index) shr 32) xor
    (Seed * $9E3779B9) xor (Channel * $85EBCA6B);
  V := (V xor (V shr 16)) * $7FEB352D;
  V := (V xor (V shr 15)) * $846CA68B;
  V := V xor (V shr 16);
  Result := V / 4294967296.0;
end;
{$IFDEF FX_RESTORE_OVERFLOW}{$Q+}{$UNDEF FX_RESTORE_OVERFLOW}{$ENDIF}
{$IFDEF FX_RESTORE_RANGE}{$R+}{$UNDEF FX_RESTORE_RANGE}{$ENDIF}

function FXNoise(Position: Double; Seed: Cardinal): Double;
var
  I: Int64;
  F, A, B: Double;
begin
  I := Floor(Position);
  F := Position - I;
  F := F * F * (3 - 2 * F);
  A := FXRandom(I, Seed, 81);
  B := FXRandom(I + 1, Seed, 81);
  Result := A + (B - A) * F;
end;

function FXProfile(Style: TFXStyle): TFXProfile;
begin
  Result := Default(TFXProfile);
  Result.Emission := feContinuous;
  Result.Life := 8;
  case Style of
    fsRain: begin
      Result.Shape := shDrop; Result.Rate := 220; Result.Speed := 850;
      Result.Size := 1.3; Result.Gravity := 50; Result.Color := $B8DFF8;
    end;
    fsSnow: begin
      Result.Shape := shSnow; Result.Rate := 75; Result.Speed := 58;
      Result.Size := 3.1; Result.Gravity := 4; Result.Sway := 20;
      Result.Color := $F1F8FF; Result.Life := 16;
    end;
    fsWater, fsFountain: begin
      Result.Shape := shDrop; Result.Rate := 240; Result.Speed := 540;
      Result.Size := 3.8; Result.Gravity := 420; Result.Color := $75CFF5;
      Result.Life := 5;
      if Style = fsWater then begin
        Result.Emission := feShot; Result.BaseAngle := 90;
      end else begin
        Result.Emission := feJet; Result.BaseAngle := 180;
      end;
    end;
    fsPetal: begin
      Result.Shape := shPetal; Result.Rate := 32; Result.Speed := 57;
      Result.Size := 5.8; Result.Gravity := 3; Result.Sway := 30;
      Result.Color := $FFBDD8; Result.Life := 16;
    end;
    fsLeaf: begin
      Result.Shape := shLeaf; Result.Rate := 22; Result.Speed := 78;
      Result.Size := 7; Result.Gravity := 5; Result.Sway := 40;
      Result.Color := $CA783B; Result.Life := 14;
    end;
    fsConfetti: begin
      Result.Shape := shPaper; Result.Rate := 65; Result.Speed := 95;
      Result.Size := 5; Result.Gravity := 8; Result.Sway := 28;
      Result.Color := $FFD966; Result.Life := 12;
    end;
    fsSand: begin
      Result.Shape := shGrain; Result.Rate := 380; Result.Speed := 220;
      Result.Size := 1.5; Result.Gravity := 80; Result.Color := $DCC399;
    end;
    fsHail: begin
      Result.Shape := shHail; Result.Rate := 95; Result.Speed := 500;
      Result.Size := 3.4; Result.Gravity := 220; Result.Color := $DBF2FA;
    end;
    fsSpark: begin
      Result.Shape := shLight; Result.Emission := feExplosion;
      Result.Rate := 180; Result.Speed := 200; Result.Size := 2.5;
      Result.Gravity := 0; Result.Color := $FFE7A2; Result.Life := 3;
    end;
    fsInk: begin
      Result.Shape := shInk; Result.Emission := feShot;
      Result.Rate := 180; Result.Speed := 450; Result.Size := 5;
      Result.Gravity := 300; Result.BaseAngle := 90;
      Result.Color := $6F54CC; Result.Life := 5;
    end;
    fsSlime: begin
      Result.Shape := shSlime; Result.Rate := 120; Result.Speed := 150;
      Result.Size := 7; Result.Gravity := 160; Result.Drag := 0.6;
      Result.Color := $65C845; Result.Life := 14;
    end;
  end;
end;

function FXDefaultSettings(Style: TFXStyle): TFXSettings;
var
  P: TFXProfile;
begin
  P := FXProfile(Style);
  Result := Default(TFXSettings);
  Result.Style := Style; Result.Emission := P.Emission; Result.Shape := P.Shape;
  Result.Seed := 1; Result.Rate := P.Rate; Result.Speed := P.Speed;
  Result.Size := P.Size; Result.Gravity := P.Gravity; Result.Angle := P.BaseAngle;
  Result.Lifetime := P.Life; Result.Sway := P.Sway; Result.Drag := P.Drag;
  Result.SizeVariation := 0.55; Result.SpeedVariation := 0.3;
  Result.DirectionSpread := 10;
  if P.Emission in [feShot, feJet] then Result.DirectionSpread := 38;
  if P.Emission = feExplosion then Result.DirectionSpread := 360;
  Result.GustPeriod := 3; Result.TurbulencePeriod := 1.4;
  Result.WindAngle := 90; Result.SwaySpeed := 1; Result.MaxSpeed := 2400;
  Result.Rotation := 75; Result.EmitterRange := 120; Result.Burst := 450;
  Result.Opacity := 0.85; Result.Aspect := 1; Result.Prewarm := 0;
  Result.AutomaticLifetime := True;
  Result.AutomaticEmitter := True;
  Result.Color := P.Color; Result.AccumColor := P.Color;
  Result.Collision := True; Result.AlphaThreshold := 128;
  Result.Bounce := 0.5; Result.Splash := 0.7; Result.SplashSpeed := 100;
  Result.ContactLife := 0.65; Result.Slide := 0.3;
  Result.Accumulation := True; Result.AccumAmount := 25;
  Result.MaxThickness := 26; Result.Roughness := 0.55;
  Result.MaxSlope := 55; Result.AccumOpacity := 1;
  Result.FloorPosition := 95; Result.MotionBlur := 0.35; Result.Depth := 0.5;
  Result.Blur := 0.6; Result.ColorVariation := 0.15;
  Result.Viscosity := 0.7; Result.Cohesion := 0.75;
  Result.Adhesion := 0.8; Result.DripTime := 1.2;
  Result.InitialState := 100;
end;

function FXStartupTiming(const S: TFXSettings; Width, Height: Integer): TFXStartupTiming;
var
  D: TFXVec;
  Distance, MinimumSpeed, Acceleration, ToLimit, LimitDistance, TravelTime, Automatic: Double;
begin
  Result := Default(TFXStartupTiming);
  Result.ParticleLifetime := S.Lifetime;
  Automatic := 0;
  if S.Emission = feContinuous then
  begin
    if S.Style = fsSlime then
      Automatic := Min(S.Lifetime, Min(8.0, Height / Max(40.0, S.Speed) + 2))
    else begin
      // 従来の自動予備動作と寿命の計算を共有し、100の表示を維持する。
      D := FXDirection(S.Angle);
      Distance := Abs(D.X) * Width + Abs(D.Y) * Height + S.Size * 8;
      MinimumSpeed := Min(S.MaxSpeed, Max(5.0, S.Speed *
        (1 - S.Depth * 0.65) * (1 - S.SpeedVariation * 0.5)));
      MinimumSpeed := MinimumSpeed / (1 + S.Drag * 2);
      Acceleration := Max(0.0, FXDot(FXDirection(S.GravityAngle), D) * S.Gravity +
        FXDot(FXDirection(S.WindAngle), D) * S.Wind);
      if Acceleration > 0.01 then
      begin
        ToLimit := Max(0.0, (S.MaxSpeed - MinimumSpeed) / Acceleration);
        LimitDistance := MinimumSpeed * ToLimit + 0.5 * Acceleration * Sqr(ToLimit);
        if Distance > LimitDistance then TravelTime := ToLimit + (Distance - LimitDistance) / S.MaxSpeed
        else TravelTime := 2 * Distance / (Sqrt(Sqr(MinimumSpeed) + 2 * Acceleration * Distance) + MinimumSpeed);
      end else TravelTime := Distance / MinimumSpeed;
      TravelTime := Min(30.0, TravelTime * 1.2);
      if S.AutomaticLifetime then Result.ParticleLifetime := Max(Result.ParticleLifetime, TravelTime);
      Automatic := Min(Result.ParticleLifetime * 1.16, TravelTime);
    end;
    if S.Prewarm > 0 then Result.FullPrewarm := S.Prewarm
    else if S.Prewarm = 0 then Result.FullPrewarm := Automatic;
  end;
  if S.InitialState >= 100 then Result.Prewarm := Result.FullPrewarm
  else Result.Prewarm := Result.FullPrewarm * (EnsureRange(S.InitialState, 0.0, 100.0) / 100);
  Result.RampTime := Max(0.1, Result.FullPrewarm);
  if Result.FullPrewarm <= 0 then Result.RampTime := Max(0.1, Automatic);
  if (Result.FullPrewarm <= 0) and (Automatic <= 0) then Result.RampTime := Max(0.1, S.Lifetime);
end;

function FXStartupAccumulation(Time: Double; const S: TFXSettings; Width, Height: Integer): Double;
var
  Timing: TFXStartupTiming;
begin
  if S.InitialState >= 100 then Exit(1);
  if (S.StartTime > 0) and (Time < S.StartTime) then Exit(0);
  Timing := FXStartupTiming(S, Width, Height);
  Result := EnsureRange(EnsureRange(S.InitialState, 0.0, 100.0) / 100 +
    (Time - S.StartTime) / Timing.RampTime, 0.0, 1.0);
end;

function FXPresetSettings(Style: TFXStyle; Preset: Integer): TFXSettings;
begin
  // 素材を指定する名前では、直前のスタイルに依存せず同じ素材を選ぶ。
  // 量・風・無重力などの共通プリセットは、現在の素材を引き継ぐ。
  case Preset of
    7: Style := fsSnow;
    11, 12: Style := fsWater;
    13..15: Style := fsFountain;
    17, 18: Style := fsSpark;
    19: Style := fsSand;
    20..22: Style := fsSlime;
  end;
  Result := FXDefaultSettings(Style);
  // ボタン適用・実験用の値を生成する。毎フレームの描画設定へ重ねて適用しない。
  case Preset of
    1: begin Result.Rate := Result.Rate * 0.35; Result.Burst := 150; end;
    2: begin Result.Rate := Result.Rate * 3; Result.Burst := 1200; end;
    3: begin Result.Wind := 160; Result.Angle := Result.Angle + 30; end;
    4: begin Result.Rate := Result.Rate * 2; Result.Wind := 280; Result.Gust := 100; end;
    5: begin Result.Rate := Result.Rate * 4; Result.Wind := 500; Result.Gust := 220; Result.Turbulence := 35; end;
    6: begin Result.Size := Result.Size * 0.5; Result.Speed := Result.Speed * 0.65; end;
    7: begin Result.Size := Result.Size * 2.2; Result.Speed := Result.Speed * 0.75; end;
    8: begin
      Result.Wind := 110;
      // 揺れる素材は風に舞わせ、雨や水流などの直進する素材は形を保つ。
      if Result.Sway > 0 then Result.Sway := Result.Sway + 25;
    end;
    9: begin Result.Angle := 180; Result.Gravity := Result.Gravity * 0.25; Result.Wind := 60; end;
    10: begin Result.Vortex := 95; Result.Wind := 40; Result.Turbulence := 20; end;
    11: begin Result.Emission := feShot; Result.Burst := 1300; Result.Size := Result.Size * 1.5; end;
    12: begin Result.Speed := Result.Speed * 1.7; Result.DirectionSpread := 12; Result.Burst := 1400; end;
    13: begin Result.Emission := feJet; Result.Rate := Result.Rate * 1.6; Result.DirectionSpread := 55; end;
    14: begin Result.Emission := feJet; Result.Duration := 1.5; Result.Period := 3; end;
    15: begin Result.Emission := feJet; Result.Rate := Result.Rate * 2; Result.DirectionSpread := 15; end;
    16: begin Result.Gravity := 0; Result.Drag := 0; Result.Sway := 0; end;
    17, 18: begin
      Result.Emission := feExplosion; Result.DirectionSpread := 360;
      Result.Burst := 750;
      if Preset = 18 then begin Result.Speed := Result.Speed * 2; Result.Glow := 0.7; end;
    end;
    19: begin Result.Angle := 90; Result.Gravity := 0; Result.Wind := 220;
      Result.Rate := Result.Rate * 3; Result.Turbulence := 30; end;
    21: begin Result.Viscosity := 0.12; Result.Cohesion := 0.35;
      Result.Adhesion := 0.3; Result.DripTime := 0.35; Result.Speed := 220; end;
    22: begin Result.Viscosity := 0.95; Result.Cohesion := 0.95;
      Result.Adhesion := 0.95; Result.DripTime := 2.4; Result.Drag := 1.2; end;
  end;
end;

function FXStyleName(Style: TFXStyle): string;
const
  Names: array[TFXStyle] of string = ('雨', '雪', '水をかける', '花びら',
    '落ち葉', '紙吹雪', '砂', 'ひょう', '噴水', '光の粒・爆発', 'インク', 'スライム');
begin
  Result := Names[Style];
end;

function FXParticleColor(const S: TFXSettings; Index: Int64): Cardinal;
const
  Palette: array[0..5] of Cardinal = ($FF668F, $FFD56A, $69DDE0,
    $9C90F5, $FEF4D0, $88D18A);
var
  R, G, B: Integer;
  Factor: Double;
begin
  Result := S.Color;
  if (S.Style = fsConfetti) and not S.CustomColor then
    Result := Palette[Min(5, Trunc(FXRandom(Index, S.Seed, 44) * 6))];
  Factor := 1 + (FXRandom(Index, S.Seed, 45) - 0.5) * S.ColorVariation;
  R := EnsureRange(Round(((Result shr 16) and 255) * Factor), 0, 255);
  G := EnsureRange(Round(((Result shr 8) and 255) * Factor), 0, 255);
  B := EnsureRange(Round((Result and 255) * Factor), 0, 255);
  Result := Cardinal((R shl 16) or (G shl 8) or B);
end;

procedure TFXVisualList.Clear;
begin
  FCount := 0;
end;

procedure TFXVisualList.Add(const Value: TFXVisual);
begin
  if FCount >= FX_MAX_PARTICLES * 6 then Exit;
  if FCount = Length(FItems) then SetLength(FItems, Max(256, FCount * 2));
  FItems[FCount] := Value;
  Inc(FCount);
end;

function TFXVisualList.GetItem(Index: Integer): TFXVisual;
begin
  Result := FItems[Index];
end;

end.
