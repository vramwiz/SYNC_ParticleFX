# ライセンスと共通基盤の由来

パーティクル演出（SYNC_ParticleFX）: Copyright (c) 2026 VRAMの魔術師

本体のソースコードはコピー元と同じGNU General Public License v3.0（GPL-3.0-only）です。全文は [LICENSE](LICENSE) を参照してください。

## AviUtl ExEdit2 Plugin SDK

- 著作権: Copyright (c) 2025 Kenkun
- ライセンス: MIT
- 対象: Source/Lib/AviUtl2FilterTypes.pasに移植したSDK型定義、コールバックと編集APIのABI定義。
- ライセンス全文: [ThirdParty/LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt)

SDKヘッダーを参照してDelphiの宣言へ移植しています。SDKのライセンス表示はソース公開時と配布ZIPの双方に同梱します。AviUtl2本体は本プロジェクトに含みません。

## 移植元・実装の参考

- **SYNC_Mine（SYNC_MINE）** — Delphiプロジェクト、SDK型定義、フィルターテーブル登録処理、配布ZIP作成とカタログJSONの基盤を引き継ぎました。
- **SYNC_PhotoShot** — Win64のDebug / Releaseビルド設定とビルドイベントを引き継ぎ、出力先フォルダー名を変更しました。
- **SYNC_Nicomea** — SYNC_Mineのプロジェクトと共通基盤の移植元です。
- **Syncroh2 / SYNC_Lyrics** — PluginFilterTable.pasの元となるフィルターテーブル登録処理です。由来はユニット先頭にも記載しています。
- **Aul2AudioFilter** — プリセットの選択・適用ボタンから編集APIを使ってAviUtl2標準項目へ一括設定する方式を参考にしました。音声処理や専用UIは含みません。

## 開発環境とサンプル

Delphi RTL / VCLとWindows標準のDirect2D・WIC・COMを使用します。開発環境・実行環境そのものは同梱しません。ZIP作成時のxxhsum.exeも開発環境から呼び出し、配布ZIPには含めません。

Sample/base.pngと実験用EXEが生成する確認画像は、このプロジェクトのプログラムで描いた素材です。外部の写真やキャラクター素材を含みません。本リポジトリで提供するこれらのサンプルもGPL-3.0-onlyです。
