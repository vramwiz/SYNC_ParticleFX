unit SYNC_ParticleFX_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 標準パラメータ、オブジェクトごとの描画資源、ホスト画像の入出力を接続する。
// 接触対象は現在のオブジェクト画像に限定し、ホストの画面は取得しない。

interface

uses
  AviUtl2FilterTypes;

// 初回に登録情報を構築し、DLL が所有するテーブルを返す。
// 呼出側で解放しない。Generator=Trueは透明なメディアオブジェクトを登録する。
function GetParticleFXFilterTable(Generator: Boolean = False): PFILTER_PLUGIN_TABLE;

const
  PARTICLEFX_REQUIRED_VERSION = 2011600;

implementation

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows,
  PluginFilterTable, ParticleFX_Types, ParticleFX_Parameters, ParticleFX_Renderer;

const
  EFFECT_NAME = 'パーティクル演出';
  EFFECT_GROUP = 'SYNC';

var
  PluginTableInitialized: Boolean;
  IsGenerator: Boolean;

type
  TParticleFXSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TFXRenderer;
    FInput, FOutput: TFXPixels;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(Video: PFILTER_PROC_VIDEO);
  end;

constructor TParticleFXSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FRenderer := TFXRenderer.Create;
end;

destructor TParticleFXSession.Destroy;
begin
  FRenderer.Free;
  FLock.Free;
  inherited;
end;

procedure TParticleFXSession.Render(Video: PFILTER_PROC_VIDEO);
var
  S: TFXSettings;
  Width, Height: Integer;
begin
  if not Assigned(Video^.SetImageData) then Exit;
  FLock.Acquire;
  try
    S := ReadParticleFXSettings;
    if IsGenerator then
    begin
      if Video^.Scene = nil then Exit;
      Width := S.CanvasWidth; Height := S.CanvasHeight;
      if Width = 0 then Width := Video^.Scene^.Width;
      if Height = 0 then Height := Video^.Scene^.Height;
    end else
    begin
      Width := Video^.Object_^.Width; Height := Video^.Object_^.Height;
      if not Assigned(Video^.GetImageData) then Exit;
    end;
    if (Width <= 0) or (Height <= 0) or (Width > 8192) or (Height > 8192) or
      (Int64(Width) * Height > FX_MAX_PIXELS) then Exit;
    SetLength(FInput, Width * Height);
    if IsGenerator then FillChar(FInput[0], Length(FInput) * SizeOf(TFXPixelRGBA), 0)
    else Video^.GetImageData(PPIXEL_RGBA(@FInput[0]));
    FRenderer.Render(FInput, Width, Height, Video^.Object_^.Time, S, FOutput);
    if Length(FOutput) = Width * Height then Video^.SetImageData(PPIXEL_RGBA(@FOutput[0]), Width, Height);
  finally
    FLock.Release;
  end;
end;

// ホストの映像処理通知を受け、成功を表す 1 を返す。
// 失敗時は元画像を維持し、フレームバッファは使用しない。
function ParticleFXProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 1;
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
    TParticleFXSession(Video^.UserData).Render(Video);
  except
    on E: Exception do
      OutputDebugString(PWideChar('SYNC_ParticleFX: ' + E.ClassName + ': ' + E.Message));
    // ホストへ例外を漏らさず、書き戻し前の入力画像を維持する。
  end;
end;

function ParticleFXCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TParticleFXSession.Create;
  except
    // 生成失敗時はuserdataなしとし、描画コールバックで入力を維持する。
  end;
end;

procedure ParticleFXDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TParticleFXSession(UserData).Free;
  except
    // DLL境界から破棄時の例外を出さない。
  end;
end;

function GetParticleFXFilterTable(Generator: Boolean): PFILTER_PLUGIN_TABLE;
var
  Flag: Integer;
begin
  if not PluginTableInitialized then
  begin
    IsGenerator := Generator;
    Flag := FILTER_FLAG_VIDEO or FILTER_FLAG_USERDATA;
    if Generator then Flag := Flag or FILTER_FLAG_INPUT else Flag := Flag or FILTER_FLAG_FILTER;
    if Generator then
      SetupPluginTable(Flag, 'パーティクル演出（単独）', EFFECT_GROUP,
        '透過背景のパーティクル演出 / Direct2D', ParticleFXProcVideo, nil)
    else
      SetupPluginTable(Flag, EFFECT_NAME, EFFECT_GROUP,
        '画像への接触・積雪と全方向の粒子演出 / Direct2D', ParticleFXProcVideo, nil);
    RegisterParticleFXParameters;
    GetPluginTable^.Func_Create := ParticleFXCreate;
    GetPluginTable^.Func_Destroy := ParticleFXDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
