library SYNC_ParticleFX;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// パーティクル演出の AviUtl2 DLL 境界。登録と終了の入口を公開する。
// Delphi 例外は C コールバックの外へ漏らさない。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  ParticleFX_Types in 'Source\Common\ParticleFX_Types.pas',
  ParticleFX_Motion in 'Source\Common\ParticleFX_Motion.pas',
  ParticleFX_Collision in 'Source\Common\ParticleFX_Collision.pas',
  ParticleFX_Simulation in 'Source\Common\ParticleFX_Simulation.pas',
  ParticleFX_Viscous in 'Source\Common\ParticleFX_Viscous.pas',
  ParticleFX_Sprites in 'Source\Common\ParticleFX_Sprites.pas',
  ParticleFX_Renderer in 'Source\Common\ParticleFX_Renderer.pas',
  ParticleFX_Parameters in 'Source\Plugin\Filter\ParticleFX_Parameters.pas',
  SYNC_ParticleFX_FilterPlugin in 'Source\Plugin\Filter\SYNC_ParticleFX_FilterPlugin.pas';

{$R *.res}

// userdataを含む公式SDKの配置を満たす本体だけで登録を有効にする。
function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if Version < PARTICLEFX_REQUIRED_VERSION then Exit;
    GetParticleFXFilterTable;
    Result := 1;
  except
    // 初期化失敗は戻り値でホストへ伝える。
  end;
end;

// 描画資源はホストがfunc_destroyを呼ぶ際、オブジェクトごとに解放する。
procedure UninitializePlugin; cdecl;
begin
end;

// 公式SDK形式の本体バージョン番号を返す。
function RequiredVersion: Cardinal; cdecl;
begin
  Result := PARTICLEFX_REQUIRED_VERSION;
end;

// DLL が所有する登録テーブルを返す。取得失敗時は nil を返す。
function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetParticleFXFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
