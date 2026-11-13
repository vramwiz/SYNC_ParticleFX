unit ParticleFX_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// AviUtl2標準項目を登録し、現在の項目値から描画設定を取り出す。
// プリセットは適用ボタンで対象エフェクトの標準項目へ一度だけ書き込む。

interface

uses
  AviUtl2FilterTypes, ParticleFX_Types;

// 空のフィルターテーブルへ項目を追加する。項目・選択肢はDLLが所有する。
procedure RegisterParticleFXParameters;
// 現在の標準項目から検証済みの値を取り出す。保存データや他オブジェクトを変更しない。
function ReadParticleFXSettings: TFXSettings;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, PluginFilterTable;

type
  TTrack = (trAmount, trSpeed, trSize, trSeed, trOffset, trStart, trDuration, trPeriod,
    trLife, trBurst, trX, trEmitterY, trRange, trAngle, trSpread, trGravity,
    trGravityAngle, trWindAngle, trWind, trGust, trGustPeriod, trTurbulence,
    trTurbulencePeriod, trVortex, trDrag, trMaxSpeed, trSway, trSwaySpeed,
    trRotation, trSizeVariation, trSpeedVariation, trAspect, trColorVariation,
    trOpacity, trThreshold, trBounce, trSplash, trSplashSpeed, trContactLife,
    trSlide, trAccumAmount, trThickness, trRoughness, trSlope, trAccumOpacity,
    trMelt, trFloor, trBlur, trMotionBlur, trGlow, trDepth, trWidth, trHeight,
    trPrewarm);
  TSelect = (slStyle, slPreset, slEmission, slResponse, slAccumShape, slDrawMode);
  TCheck = (ckCollision, ckAccumulation, ckFloor, ckColor, ckAccumColor, ckAutoEmitter);

var
  Tracks: array[TTrack] of TFILTER_ITEM_TRACK;
  Selects: array[TSelect] of TFILTER_ITEM_SELECT;
  Options: array[TSelect, 0..21] of TFILTER_ITEM_SELECT_ITEM;
  Checks: array[TCheck] of TFILTER_ITEM_CHECK;
  Groups, GroupEnds: array[0..6] of TFILTER_ITEM_GROUP;
  ParticleColor, AccumColor: TFILTER_ITEM_COLOR;
  PresetButton: TFILTER_ITEM_BUTTON;

// SDKの編集セクションで全項目を更新する。選択だけでは現在の設定へ影響しない。
procedure ApplyPresetButton(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE;
  Effect, Item: PWideChar); cdecl;
var
  Base, Preset: TFXSettings;
  Amount: Double;
  TargetEffect: string;

  procedure SetItem(Name: PWideChar; const Text: UTF8String);
  begin
    if not Edit^.SetObjectItemValue(Obj, PWideChar(TargetEffect), Name,
      PAnsiChar(Text)) then
      raise EInvalidOp.CreateFmt('Preset item could not be set: %s', [string(Name)]);
  end;

  procedure SetTrack(TrackItem: TTrack; Number: Double);
  begin
    Number := EnsureRange(Number, Tracks[TrackItem].S, Tracks[TrackItem].E);
    SetItem(Tracks[TrackItem].Name, UTF8String(FloatToStr(Number, TFormatSettings.Invariant)));
    Tracks[TrackItem].Value := Number;
  end;

begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) then Exit;
  if not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    // callback2の対象名をそのまま使い、同じフィルターの2個目以降も区別する。
    TargetEffect := Effect;
    Base := FXDefaultSettings(TFXStyle(EnsureRange(Selects[slStyle].Value, 0, FX_STYLE_COUNT - 1)));
    Preset := FXPresetSettings(Base.Style, Selects[slPreset].Value);
    Amount := Preset.Rate / Base.Rate * 100;
    SetTrack(trAmount, Amount);
    SetTrack(trSize, Preset.Size / Base.Size * 100);
    SetTrack(trSpeed, Preset.Speed / Base.Speed * 100);
    SetItem(Selects[slEmission].Name, UTF8String(IntToStr(Ord(Preset.Emission) + 1)));
    Selects[slEmission].Value := Ord(Preset.Emission) + 1;
    SetTrack(trDuration, Preset.Duration);
    SetTrack(trPeriod, Preset.Period);
    SetTrack(trLife, 0);
    // 発生量の倍率は瞬間発生にも掛かるので、二重に増えない値へ戻す。
    SetTrack(trBurst, Preset.Burst * 100 / Amount);
    SetTrack(trAngle, Preset.Angle - Base.Angle);
    SetTrack(trSpread, Preset.DirectionSpread);
    SetTrack(trGravity, Preset.Gravity);
    SetTrack(trGravityAngle, Preset.GravityAngle);
    SetTrack(trWindAngle, Preset.WindAngle - 90);
    SetTrack(trWind, Preset.Wind - Base.Wind);
    SetTrack(trGust, Preset.Gust - Base.Gust);
    SetTrack(trGustPeriod, Preset.GustPeriod);
    SetTrack(trTurbulence, Preset.Turbulence - Base.Turbulence);
    SetTrack(trTurbulencePeriod, Preset.TurbulencePeriod);
    SetTrack(trVortex, Preset.Vortex - Base.Vortex);
    SetTrack(trDrag, Preset.Drag - Base.Drag);
    SetTrack(trMaxSpeed, Preset.MaxSpeed);
    if Base.Sway > 0 then SetTrack(trSway, Preset.Sway / Base.Sway * 100)
    else SetTrack(trSway, 100);
    SetTrack(trSwaySpeed, Preset.SwaySpeed);
    SetTrack(trGlow, (Preset.Glow - Base.Glow) * 100);
    // 配置・開始時刻・シード・色・接触・蓄積・描画範囲は個別設定を維持する。
  except
    on E: Exception do
      OutputDebugString(PWideChar('SYNC_ParticleFX preset: ' + E.Message));
  end;
end;

procedure Track(Item: TTrack; Name: PWideChar; Value, Low, High: Double;
  Step: Double = 1);
begin
  AddTrack(Tracks[Item], Name, Value, Low, High, Step);
end;

procedure Select(Item: TSelect; Name: PWideChar; const Names: array of PWideChar);
var
  I: Integer;
begin
  for I := 0 to High(Names) do
  begin
    Options[Item, I].Name := Names[I];
    Options[Item, I].Value := I;
  end;
  AddSelect(Selects[Item], Name, 0, @Options[Item, 0]);
end;

procedure RegisterParticleFXParameters;
begin
  Select(slPreset, 'プリセット', ['標準', '小雨・少量', '豪雨・大量', '横殴り・横風',
    '暴風雨・吹雪', '嵐・猛吹雪', '霧雨・粉雪', 'ぼたん雪', '風に流される',
    '舞い上がる', '渦巻き・竜巻', 'バケツ', '強い水流', 'シャワー',
    '間欠噴出', '連続噴射', '無重力', '全方向放射', '爆発', '砂嵐']);
  AddButton(PresetButton, 'プリセット適用', ApplyPresetButton);
  Select(slStyle, 'スタイル', ['雨', '雪', '水をかける', '花びら', '落ち葉',
    '紙吹雪', '砂', 'ひょう', '噴水', '光の粒・爆発', 'インク']);
  Track(trAmount, '発生量(%)', 100, 0, 1000);
  Track(trSize, '粒子サイズ(%)', 100, 1, 1000);
  Track(trSpeed, '初速度(%)', 100, 0, 1000);
  Track(trSeed, 'ランダムシード', 1, 0, 1000000);
  Track(trOffset, '時間オフセット(秒)', 0, -3600, 3600, 0.01);

  AddGroup(Groups[0], '発生', 0);
  Select(slEmission, '発生方式', ['スタイル既定', '連続', '発射', '爆発・放射', '噴出']);
  AddCheck(Checks[ckAutoEmitter], '発生位置を自動', 1);
  Track(trX, '発生位置X', 0, -8192, 8192, 0.1);
  Track(trEmitterY, '発生位置Y', 0, -8192, 8192, 0.1);
  Track(trRange, '発生範囲(%)', 120, 0, 400);
  Track(trStart, '発生開始(秒)', 0, 0, 3600, 0.01);
  Track(trDuration, '発生時間(0=無制限)', 0, 0, 3600, 0.01);
  Track(trPeriod, '繰返し周期(0=既定)', 0, 0, 60, 0.1);
  Track(trBurst, '瞬間発生量', 450, 0, 12000);
  Track(trLife, '寿命(0=スタイル既定)', 0, 0, 30, 0.1);
  Track(trPrewarm, '予備動作(-1=無/0=自動)', 0, -1, 30, 0.1);
  AddGroup(GroupEnds[0], '', 1);

  AddGroup(Groups[1], '方向・風・運動', 0);
  Track(trAngle, '発生角度(0=基準方向)', 0, -360, 360, 0.1);
  Track(trSpread, '広がり角(-1=スタイル既定)', -1, -1, 360, 0.1);
  Track(trGravity, '重力強度(-1=スタイル既定)', -1, -1, 3000);
  Track(trGravityAngle, '重力方向(0=下)', 0, -360, 360, 0.1);
  Track(trWindAngle, '風向(0=右)', 0, -360, 360, 0.1);
  Track(trWind, '風力調整', 0, -2000, 2000);
  Track(trGust, '突風強度調整', 0, -2000, 2000);
  Track(trGustPeriod, '突風周期(秒)', 3, 0.1, 30, 0.1);
  Track(trTurbulence, '乱流強度調整', 0, -1000, 1000);
  Track(trTurbulencePeriod, '乱流周期(秒)', 1.4, 0.1, 20, 0.1);
  Track(trVortex, '渦回転調整(度/秒)', 0, -720, 720);
  Track(trDrag, '空気抵抗', 0, 0, 10, 0.01);
  Track(trMaxSpeed, '最大速度', 2400, 1, 10000);
  Track(trSway, '揺れ幅(%)', 100, 0, 500);
  Track(trSwaySpeed, '揺れ速度', 1, 0, 10, 0.1);
  AddGroup(GroupEnds[1], '', 1);

  AddGroup(Groups[2], '粒子の外観', 0);
  Track(trSizeVariation, 'サイズのばらつき(%)', 55, 0, 100);
  Track(trSpeedVariation, '速度のばらつき(%)', 30, 0, 100);
  Track(trAspect, '縦横比', 1, 0.1, 10, 0.1);
  Track(trRotation, '回転速度(度/秒)', 75, -720, 720);
  AddCheck(Checks[ckColor], '粒子色を指定', 0);
  AddColor(ParticleColor, '粒子色', 255, 255, 255);
  Track(trColorVariation, '色のばらつき(%)', 15, 0, 100);
  Track(trOpacity, '粒子不透明度(%)', 85, 0, 100);
  Track(trDepth, '遠近感(%)', 50, 0, 100);
  AddGroup(GroupEnds[2], '', 1);

  AddGroup(Groups[3], '接触', 1);
  AddCheck(Checks[ckCollision], '画像と接触する', 1);
  Track(trThreshold, 'アルファ判定しきい値', 128, 1, 255);
  Select(slResponse, '接触反応', ['素材に合わせる', '跳ね返る', '付着する', '消滅する']);
  Track(trBounce, '反発力(%)', 50, 0, 100);
  Track(trSplash, '飛散量(%)', 70, 0, 200);
  Track(trSplashSpeed, '飛散速度', 100, 0, 1000);
  Track(trContactLife, '接触効果時間(秒)', 0.65, 0.05, 5, 0.05);
  Track(trSlide, '滑落しやすさ(%)', 30, 0, 100);
  AddGroup(GroupEnds[3], '', 1);

  AddGroup(Groups[4], '蓄積', 1);
  AddCheck(Checks[ckAccumulation], '蓄積を描画', 1);
  Track(trAccumAmount, '蓄積量', 25, 0, 100, 0.1);
  Track(trThickness, '最大蓄積厚', 26, 0, 300, 0.1);
  Select(slAccumShape, '蓄積形状', ['輪郭', '水平(床)', '部分蓄積', '薄く付着']);
  Track(trRoughness, '蓄積のばらつき(%)', 55, 0, 100);
  Track(trSlope, '蓄積可能な傾斜', 55, 0, 89);
  AddCheck(Checks[ckAccumColor], '蓄積色を指定', 0);
  AddColor(AccumColor, '蓄積色', 255, 255, 255);
  Track(trAccumOpacity, '蓄積不透明度(%)', 100, 0, 100);
  Track(trMelt, '消失速度(%/秒)', 0, 0, 100, 0.1);
  AddCheck(Checks[ckFloor], '床を有効にする', 0);
  Track(trFloor, '床位置(上から%)', 95, 0, 100, 0.1);
  AddGroup(GroupEnds[4], '', 1);

  AddGroup(Groups[5], '描画品質', 0);
  Track(trBlur, '輪郭の柔らかさ', 0.6, 0, 5, 0.1);
  Track(trMotionBlur, 'モーションブラー(%)', 35, 0, 100);
  Track(trGlow, '発光強度調整(%)', 0, -200, 200);
  AddGroup(GroupEnds[5], '', 1);

  AddGroup(Groups[6], '適用方法・描画範囲', 0);
  Select(slDrawMode, '描画モード', ['元画像に重ねる', 'パーティクルのみ', '接触・蓄積のみ']);
  Track(trWidth, '単独の幅(0=シーン)', 0, 0, 8192);
  Track(trHeight, '単独の高さ(0=シーン)', 0, 0, 8192);
  AddGroup(GroupEnds[6], '', 1);
end;

function Value(Item: TTrack): Double;
begin
  Result := Tracks[Item].Value;
  if IsNan(Result) or IsInfinite(Result) then Result := 0;
  Result := EnsureRange(Result, Tracks[Item].S, Tracks[Item].E);
end;

function ColorValue(const Item: TFILTER_ITEM_COLOR): Cardinal;
begin
  Result := (Cardinal(Item.R) shl 16) or (Cardinal(Item.G) shl 8) or Item.B;
end;

function ReadParticleFXSettings: TFXSettings;
begin
  Result := FXDefaultSettings(TFXStyle(EnsureRange(Selects[slStyle].Value, 0, FX_STYLE_COUNT - 1)));
  if Selects[slEmission].Value in [1..4] then
    Result.Emission := TFXEmission(Selects[slEmission].Value - 1);
  Result.Rate := Min(3000.0, Result.Rate * Value(trAmount) / 100);
  Result.Speed := Result.Speed * Value(trSpeed) / 100;
  Result.Size := Result.Size * Value(trSize) / 100;
  Result.Seed := Round(Value(trSeed)); Result.Offset := Value(trOffset);
  Result.StartTime := Value(trStart);
  if Value(trDuration) > 0 then Result.Duration := Value(trDuration);
  if Value(trPeriod) > 0 then Result.Period := Max(0.1, Value(trPeriod));
  if Value(trLife) > 0 then begin
    Result.Lifetime := Value(trLife); Result.AutomaticLifetime := False;
  end;
  Result.Burst := Result.Burst * Value(trBurst) / 450 * Value(trAmount) / 100;
  Result.EmitterX := Value(trX); Result.EmitterY := Value(trEmitterY);
  Result.AutomaticEmitter := Checks[ckAutoEmitter].Value <> 0;
  Result.EmitterRange := Value(trRange); Result.Angle := Result.Angle + Value(trAngle);
  if Value(trSpread) >= 0 then Result.DirectionSpread := Value(trSpread);
  if Value(trGravity) >= 0 then Result.Gravity := Value(trGravity);
  Result.GravityAngle := Value(trGravityAngle);
  Result.WindAngle := 90 + Value(trWindAngle); Result.Wind := Result.Wind + Value(trWind);
  Result.Gust := Max(0.0, Result.Gust + Value(trGust)); Result.GustPeriod := Value(trGustPeriod);
  Result.Turbulence := Max(0.0, Result.Turbulence + Value(trTurbulence));
  Result.TurbulencePeriod := Value(trTurbulencePeriod);
  Result.Vortex := Result.Vortex + Value(trVortex); Result.Drag := Result.Drag + Value(trDrag);
  Result.MaxSpeed := Value(trMaxSpeed);
  Result.Sway := Result.Sway * Value(trSway) / 100;
  Result.SwaySpeed := Value(trSwaySpeed); Result.Rotation := Value(trRotation);
  Result.SizeVariation := Value(trSizeVariation) / 100;
  Result.SpeedVariation := Value(trSpeedVariation) / 100;
  Result.Aspect := Value(trAspect); Result.ColorVariation := Value(trColorVariation) / 100;
  Result.Opacity := Value(trOpacity) / 100; Result.Depth := Value(trDepth) / 100;
  Result.CustomColor := Checks[ckColor].Value <> 0;
  if Result.CustomColor then Result.Color := ColorValue(ParticleColor);
  Result.Collision := Checks[ckCollision].Value <> 0;
  Result.AlphaThreshold := Round(Value(trThreshold));
  Result.Response := EnsureRange(Selects[slResponse].Value, 0, 3);
  Result.Bounce := Value(trBounce) / 100; Result.Splash := Value(trSplash) / 100;
  Result.SplashSpeed := Value(trSplashSpeed); Result.ContactLife := Value(trContactLife);
  Result.Slide := Value(trSlide) / 100;
  Result.Accumulation := Checks[ckAccumulation].Value <> 0;
  Result.AccumAmount := Value(trAccumAmount); Result.MaxThickness := Value(trThickness);
  Result.AccumShape := EnsureRange(Selects[slAccumShape].Value, 0, 3);
  Result.Roughness := Value(trRoughness) / 100; Result.MaxSlope := Value(trSlope);
  Result.CustomAccumColor := Checks[ckAccumColor].Value <> 0;
  if Result.CustomAccumColor then Result.AccumColor := ColorValue(AccumColor)
  else Result.AccumColor := Result.Color;
  Result.AccumOpacity := Value(trAccumOpacity) / 100; Result.Melt := Value(trMelt);
  Result.FloorEnabled := (Checks[ckFloor].Value <> 0) or (Result.AccumShape = 1);
  Result.FloorPosition := Value(trFloor); Result.Blur := Value(trBlur);
  Result.MotionBlur := Value(trMotionBlur) / 100;
  Result.Glow := Max(0.0, Result.Glow + Value(trGlow) / 100);
  Result.CanvasWidth := Round(Value(trWidth)); Result.CanvasHeight := Round(Value(trHeight));
  Result.DrawMode := EnsureRange(Selects[slDrawMode].Value, 0, 2);
  Result.Prewarm := Value(trPrewarm);
end;

end.
