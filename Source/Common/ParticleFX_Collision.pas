unit ParticleFX_Collision;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 元画像のアルファだけを接触マスクにし、重力に面した輪郭から蓄積を生成する。
// 粒子の描画結果は元のマスクに混ぜず、同じ入力と設定から毎回再現できる。

interface

uses
  ParticleFX_Types;

type
  TFXSurface = record
    Base, Tip, Normal: TFXVec;
    Thickness: Double;
    Valid, IsCoating: Boolean;
  end;

  TFXEnvironment = class
  private
    FWidth, FHeight, FSourceHeight, FSolidCount, FRevision: Integer;
    FMask, FAccumMask: TArray<Byte>;
    FSurfaces: TArray<TFXSurface>;
    FSurfaceCount: Integer;
    FSettings: TFXSettings;
    FLastAmount, FFloorY: Double;
    FPrepared, FFloorEnabled: Boolean;
    function OriginalSolid(X, Y: Integer): Boolean; inline;
    function Solid(X, Y: Integer): Boolean; inline;
    function NormalAt(X, Y: Integer; const Fallback: TFXVec;
      IncludeAccumulation: Boolean): TFXVec;
    procedure AddSurface(const Position, Normal: TFXVec; Thickness: Double;
      Coating: Boolean = False);
    procedure StampSurface(const Surface: TFXSurface);
    procedure BuildSurfaces(const S: TFXSettings; Amount: Double);
    function GetSurface(Index: Integer): TFXSurface;
    function GetHasObstacles: Boolean;
  public
    // 入力はストレートRGBA。バッファを保持・変更せず、二値マスクだけを複製する。
    // 蓄積は量と現在時刻から作り、入力変更時は輪郭キャッシュを更新する。
    procedure Prepare(const Input: TFXPixels; Width, Height: Integer;
      const Settings: TFXSettings; Time: Double; SourceHeight: Integer = 0);
    // 元のアルファだけを参照する。前面へ滴下した粒子が画像を抜けたか調べる。
    function ContainsImage(const Position: TFXVec): Boolean;
    // 区間を走査して最初の接触位置と法線を返す。画面外へはアクセスしない。
    // 輪郭追従ではPreserveNormalを指定し、面から離れる移動を接触させない。
    function Trace(const A, B: TFXVec; Radius: Double;
      out HitPosition, Normal: TFXVec; out Fraction: Double;
      PreserveNormal: Boolean = False): Boolean;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property SourceHeight: Integer read FSourceHeight;
    property FloorY: Double read FFloorY;
    property Revision: Integer read FRevision;
    property SurfaceCount: Integer read FSurfaceCount;
    property Surfaces[Index: Integer]: TFXSurface read GetSurface;
    property HasObstacles: Boolean read GetHasObstacles;
  end;

implementation

uses
  System.Math, System.SysUtils;

function TFXEnvironment.OriginalSolid(X, Y: Integer): Boolean;
begin
  Result := (X >= 0) and (X < FWidth) and (Y >= 0) and (Y < FHeight);
  if Result then Result := FMask[Y * FWidth + X] <> 0;
end;

function TFXEnvironment.Solid(X, Y: Integer): Boolean;
begin
  Result := (X >= 0) and (X < FWidth) and (Y >= 0) and (Y < FHeight);
  if not Result then Exit;
  if FFloorEnabled and (Y >= FFloorY) then Exit(True);
  Result := (FMask[Y * FWidth + X] <> 0) or (FAccumMask[Y * FWidth + X] <> 0);
end;

function TFXEnvironment.NormalAt(X, Y: Integer; const Fallback: TFXVec;
  IncludeAccumulation: Boolean): TFXVec;
var
  I, NX, NY: Integer;
  function Occupied(PX, PY: Integer): Integer;
  begin
    if IncludeAccumulation then Result := Ord(Solid(PX, PY))
    else Result := Ord(OriginalSolid(PX, PY));
  end;
begin
  if IncludeAccumulation and FFloorEnabled and (Y >= FFloorY - 1) then
    Exit(FXVec(0, -1));
  NX := 0; NY := 0;
  for I := -2 to 2 do
  begin
    Inc(NX, Occupied(X - 2, Y + I) - Occupied(X + 2, Y + I));
    Inc(NY, Occupied(X + I, Y - 2) - Occupied(X + I, Y + 2));
  end;
  if (NX = 0) and (NY = 0) then Result := Fallback
  else Result := FXNormalize(FXVec(NX, NY));
end;

procedure TFXEnvironment.Prepare(const Input: TFXPixels; Width, Height: Integer;
  const Settings: TFXSettings; Time: Double; SourceHeight: Integer);
var
  I, Count: Integer;
  Changed, StaticAccumulation: Boolean;
  Occupied: Byte;
  Amount: Double;
begin
  if (Width < 1) or (Height < 1) or (Int64(Width) * Height > FX_MAX_PIXELS) or
    (Length(Input) <> Width * Height) then
    raise EArgumentException.Create('パーティクル演出の画像サイズが不正です。');
  Count := Width * Height;
  if SourceHeight <= 0 then SourceHeight := Height;
  Changed := not FPrepared or (FWidth <> Width) or (FHeight <> Height) or
    (FSourceHeight <> SourceHeight);
  FWidth := Width; FHeight := Height;
  FSourceHeight := SourceHeight;
  if Length(FMask) <> Count then
  begin
    SetLength(FMask, Count);
    SetLength(FAccumMask, Count);
  end;
  FSolidCount := 0;
  for I := 0 to Count - 1 do
  begin
    Occupied := Ord((Input[I].A > 0) and (Input[I].A >= Settings.AlphaThreshold));
    if FMask[I] <> Occupied then Changed := True;
    FMask[I] := Occupied;
    Inc(FSolidCount, Occupied);
  end;
  Amount := EnsureRange(Settings.AccumAmount - Max(0.0, Time) * Settings.Melt, 0.0, 100.0);
  StaticAccumulation := Settings.Accumulation and (Settings.MaxThickness > 0) and
    (Settings.Style in [fsSnow, fsPetal, fsLeaf, fsConfetti, fsSand, fsHail, fsInk]);
  // 粘性の付着は粒子の履歴から生まれるため、静的な蓄積だけを進行に合わせる。
  if StaticAccumulation and (Settings.InitialState < 100) then
    Amount := Amount * FXStartupAccumulation(Time, Settings, Width, Height);
  if not Changed and CompareMem(@FSettings, @Settings, SizeOf(Settings)) and
    (FLastAmount = Amount) then Exit;
  FSettings := Settings;
  Inc(FRevision);
  FLastAmount := Amount;
  FFloorEnabled := Settings.FloorEnabled;
  FFloorY := EnsureRange(Settings.FloorPosition / 100 * FSourceHeight, 0.0, Height - 1.0);
  FillChar(FAccumMask[0], Count, 0);
  FSurfaceCount := 0;
  if StaticAccumulation and (Amount > 0) then BuildSurfaces(Settings, Amount);
  FPrepared := True;
end;

function TFXEnvironment.ContainsImage(const Position: TFXVec): Boolean;
begin
  Result := OriginalSolid(Round(Position.X), Round(Position.Y));
end;

procedure TFXEnvironment.AddSurface(const Position, Normal: TFXVec; Thickness: Double;
  Coating: Boolean);
var
  Surface: TFXSurface;
begin
  if FSurfaceCount = Length(FSurfaces) then SetLength(FSurfaces, Max(256, FSurfaceCount * 2));
  Surface := Default(TFXSurface);
  Surface.Base := Position; Surface.Normal := Normal; Surface.Thickness := Thickness;
  Surface.Tip := FXVec(Position.X + Normal.X * Thickness, Position.Y + Normal.Y * Thickness);
  Surface.Valid := Thickness > 0.05;
  Surface.IsCoating := Coating;
  FSurfaces[FSurfaceCount] := Surface;
  Inc(FSurfaceCount);
  if Surface.Valid then StampSurface(Surface);
end;

procedure TFXEnvironment.StampSurface(const Surface: TFXSurface);
var
  CX, CY, RX, RY, DX, DY, Along, Across, NormalRadius: Double;
  X, Y, X0, Y0, X1, Y1: Integer;
begin
  NormalRadius := Surface.Thickness * 0.5 + 0.8;
  CX := Surface.Base.X + Surface.Normal.X * (Surface.Thickness * 0.5 - 0.6);
  CY := Surface.Base.Y + Surface.Normal.Y * (Surface.Thickness * 0.5 - 0.6);
  RX := Abs(Surface.Normal.X) * NormalRadius + Abs(Surface.Normal.Y) * 1.6;
  RY := Abs(Surface.Normal.Y) * NormalRadius + Abs(Surface.Normal.X) * 1.6;
  X0 := Max(0, Floor(CX - RX)); X1 := Min(FWidth - 1, Ceil(CX + RX));
  Y0 := Max(0, Floor(CY - RY)); Y1 := Min(FHeight - 1, Ceil(CY + RY));
  for Y := Y0 to Y1 do
    for X := X0 to X1 do
    begin
      DX := X + 0.5 - CX; DY := Y + 0.5 - CY;
      Along := (DX * Surface.Normal.X + DY * Surface.Normal.Y) / NormalRadius;
      Across := (-DX * Surface.Normal.Y + DY * Surface.Normal.X) / 1.6;
      if Sqr(Along) + Sqr(Across) <= 1 then FAccumMask[Y * FWidth + X] := 1;
    end;
end;

procedure TFXEnvironment.BuildSurfaces(const S: TFXSettings; Amount: Double);
var
  G, Incoming, P: TFXVec;
  Thickness, MinimumFacing, SidePower, DirectionDot: Double;
  X: Integer;
  function LocalThickness(Position: Double; Weight: Double): Double;
  var
    Factor, Noise: Double;
  begin
    Noise := FXNoise(Position / 24, S.Seed);
    Factor := 1 - S.Roughness * 0.6 + Noise * S.Roughness * 0.6;
    if S.AccumShape = 2 then Factor := Factor * EnsureRange((Noise - 0.38) * 2.2, 0.0, 1.0);
    Result := S.MaxThickness * Amount / 100 * Factor * Weight;
    if S.AccumShape = 3 then Result := Min(Result, 3.5 * Amount / 100);
  end;

  procedure Scan(const Direction: TFXVec; Weight: Double; Coating: Boolean);
  var
    T, Start, Position, Normal, Center: TFXVec;
    UExtent, VExtent, Facing, Support, SlopeWeight, LocalDepth: Double;
    U, V, UCount, VCount, X, Y: Integer;
    Found: Boolean;
  begin
    T := FXVec(Direction.Y, -Direction.X);
    Center := FXVec(FWidth * 0.5, FHeight * 0.5);
    UExtent := Abs(T.X) * FWidth * 0.5 + Abs(T.Y) * FHeight * 0.5;
    VExtent := Abs(Direction.X) * FWidth * 0.5 + Abs(Direction.Y) * FHeight * 0.5;
    UCount := Ceil(UExtent); VCount := Ceil(VExtent * 2 + 4);
    for U := -UCount to UCount do
    begin
      Start := FXVec(Center.X + T.X * U - Direction.X * (VExtent + 2),
        Center.Y + T.Y * U - Direction.Y * (VExtent + 2));
      Position := Start; Found := False; X := 0; Y := 0;
      for V := 0 to VCount do
      begin
        X := Round(Position.X); Y := Round(Position.Y);
        if OriginalSolid(X, Y) then begin Found := True; Break; end;
        Position.X := Position.X + Direction.X; Position.Y := Position.Y + Direction.Y;
      end;
      LocalDepth := 0;
      Normal := FXVec(-Direction.X, -Direction.Y);
      if Found then
      begin
        Normal := NormalAt(X, Y, Normal, False);
        Facing := -FXDot(Normal, Direction);
        Support := -FXDot(Normal, G);
        if Coating then
        begin
          // 風上の側面には薄い付着だけを加える。上面の厚い蓄積と下向き面を避ける。
          if (Facing > 0.45) and (Support < MinimumFacing - 0.05) and (Support >= -0.05) then
            LocalDepth := Min(3.5 * Amount / 100, LocalThickness(U, 0.18 * Weight)) * (Facing - 0.45) / 0.55;
        end else if Facing >= MinimumFacing - 0.001 then
        begin
          if MinimumFacing >= 0.999 then SlopeWeight := 1
          else SlopeWeight := EnsureRange((Facing - MinimumFacing) / (1 - MinimumFacing), 0.0, 1.0);
          LocalDepth := LocalThickness(U, Power(Max(0.0, Facing), 1.2) * Sqrt(SlopeWeight));
        end;
      end;
      AddSurface(Position, Normal, LocalDepth, Coating);
    end;
  end;
begin
  G := FXDirection(S.GravityAngle);
  MinimumFacing := Cos(DegToRad(S.MaxSlope));
  if (FSolidCount > 0) and (S.AccumShape <> 1) then
  begin
    // 蓄積の主形状は重力、薄い側面付着だけを風・飛来方向から求める。
    Scan(G, 1, False);
    Incoming := FXDirection(S.Angle);
    if Abs(S.Wind) > 1 then
    begin
      Incoming := FXDirection(S.WindAngle);
      if S.Wind < 0 then Incoming := FXVec(-Incoming.X, -Incoming.Y);
    end;
    DirectionDot := EnsureRange(FXDot(Incoming, G), -1.0, 1.0);
    SidePower := Max(Min(1.0, Abs(S.Wind) / Max(1.0, S.Speed * 1.5)),
      Sqrt(Max(0.0, 1 - Sqr(DirectionDot))));
    if SidePower > 0.1 then
    begin
      AddSurface(FXVec(0, 0), FXVec(0, -1), 0);
      Scan(Incoming, SidePower, True);
    end;
  end;
  // 画像の輪郭と床の間を結ばない。床は世界座標の水平面として維持する。
  AddSurface(FXVec(0, 0), FXVec(0, -1), 0);
  if S.FloorEnabled then
    for X := 0 to FWidth div 2 do
    begin
      P := FXVec(X * 2, FFloorY);
      Thickness := 0;
      if G.Y > MinimumFacing then Thickness := LocalThickness(X * 2, G.Y);
      AddSurface(P, FXVec(0, -1), Thickness);
    end;
end;

function TFXEnvironment.Trace(const A, B: TFXVec; Radius: Double;
  out HitPosition, Normal: TFXVec; out Fraction: Double; PreserveNormal: Boolean): Boolean;
var
  D, Direction, Perpendicular, Probe, SurfaceProbe, Fallback: TFXVec;
  Steps, I, J, K, ProbeSteps, X, Y: Integer;
  Offset: Double;
begin
  Result := False;
  if not HasObstacles then Exit;
  // 内側からの支持面探索で、その始点を新しい表面として返さない。
  if PreserveNormal and Solid(Round(A.X), Round(A.Y)) then Exit;
  if ((A.X < -Radius) and (B.X < -Radius)) or
    ((A.X >= FWidth + Radius) and (B.X >= FWidth + Radius)) or
    ((A.Y < -Radius) and (B.Y < -Radius)) or
    ((A.Y >= FHeight + Radius) and (B.Y >= FHeight + Radius)) then Exit;
  D := FXVec(B.X - A.X, B.Y - A.Y);
  Direction := FXNormalize(D);
  Perpendicular := FXVec(Direction.Y, -Direction.X);
  Steps := Max(1, Ceil(Max(Abs(D.X), Abs(D.Y))));
  for I := 0 to Steps do
  begin
    Fraction := I / Steps;
    HitPosition := FXVec(A.X + D.X * Fraction, A.Y + D.Y * Fraction);
    for J := -1 to 1 do
    begin
      Offset := J * Radius * 0.55;
      Probe := FXVec(HitPosition.X + Direction.X * Radius + Perpendicular.X * Offset,
        HitPosition.Y + Direction.Y * Radius + Perpendicular.Y * Offset);
      X := Round(Probe.X); Y := Round(Probe.Y);
      if not Solid(X, Y) then Continue;
      Fallback := FXVec(-Direction.X, -Direction.Y);
      if PreserveNormal then
      begin
        // 半径の先端は画像の奥に届くため、そこではなく最初の境界で法線を求める。
        // 細い輪郭で勾配が取れない場合も、中心へ戻る向きを使い内側へ反転させない。
        ProbeSteps := Max(1, Ceil(Max(Abs(Probe.X - HitPosition.X), Abs(Probe.Y - HitPosition.Y))));
        SurfaceProbe := Probe;
        for K := 0 to ProbeSteps do
        begin
          SurfaceProbe := FXVec(HitPosition.X + (Probe.X - HitPosition.X) * K / ProbeSteps,
            HitPosition.Y + (Probe.Y - HitPosition.Y) * K / ProbeSteps);
          if Solid(Round(SurfaceProbe.X), Round(SurfaceProbe.Y)) then Break;
        end;
        X := Round(SurfaceProbe.X); Y := Round(SurfaceProbe.Y);
        Fallback := FXNormalize(FXVec(HitPosition.X - SurfaceProbe.X, HitPosition.Y - SurfaceProbe.Y));
        if FXLength(Fallback) < 0.5 then Fallback := FXVec(-Direction.X, -Direction.Y);
      end;
      Normal := NormalAt(X, Y, Fallback, True);
      if PreserveNormal then
      begin
        // 横の探索点が触れていても、実際に面から離れる粒子を引き戻さない。
        if FXDot(Normal, Direction) > 1E-6 then Continue;
      end else if FXDot(Normal, Direction) > 0 then
        Normal := FXVec(-Normal.X, -Normal.Y);
      Exit(True);
    end;
  end;
end;

function TFXEnvironment.GetSurface(Index: Integer): TFXSurface;
begin
  Result := FSurfaces[Index];
end;

function TFXEnvironment.GetHasObstacles: Boolean;
begin
  Result := (FSolidCount > 0) or FFloorEnabled;
end;

end.
