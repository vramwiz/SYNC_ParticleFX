param(
    [string]$ReleaseDirectory,
    [string]$XxhsumPath
)

# SYNC_Mine由来。既存AUF2を梱包し、末尾バージョンのハッシュを更新する。
# ビルド・ホスト起動・ネットワークへの公開は行わない。
# Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
$ErrorActionPreference = 'Stop'
$packageName = 'SYNC_ParticleFX'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = 'C:\ProgramData\aviutl2\Plugin\SYNC_ParticleFX' }
$pluginName = "$packageName.auf2"
$pluginPath = Join-Path $ReleaseDirectory $pluginName
if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "Release plugin not found: $pluginPath. Build the Win64 Release configuration first."
}

if (-not $XxhsumPath) {
    $XxhsumPath = Join-Path $projectDir 'Win64\Dependencies\xxHash-0.8.4\xxhsum.exe'
    if (-not (Test-Path -LiteralPath $XxhsumPath -PathType Leaf)) {
        $xxhsum = Get-Command xxhsum.exe -CommandType Application -ErrorAction SilentlyContinue
        if (-not $xxhsum) { throw 'xxhsum.exe is required. See setup\README.md.' }
        $XxhsumPath = $xxhsum.Source
    }
}
$XxhsumPath = (Resolve-Path -LiteralPath $XxhsumPath).ProviderPath

$catalogPath = Join-Path $PSScriptRoot "$packageName.catalog.json"
$zipPath = Join-Path $PSScriptRoot "$packageName.zip"
$tempBase = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N'))
$tempPlugin = "$tempBase-plugin.tmp"
$tempZip = "$tempBase-zip.tmp"
$tempCatalog = "$tempBase-catalog.tmp"
$tempNotices = "$tempBase-notices.tmp"
$catalogBackup = "$tempBase-previous-catalog.tmp"

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$lock = [Threading.Mutex]::new($false, 'Local\VRAMWIZ.SYNC_ParticleFX.ReleaseZip')
$ownsLock = $false
try {
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Another release ZIP is being created. Run the batch again.' }

    $catalogSource = [IO.File]::ReadAllText($catalogPath)
    $catalog = [object[]]($catalogSource | ConvertFrom-Json)
    $version = $catalog[0].version[-1]
    $pluginEntry = @($version.file | Where-Object path -ceq "{pluginsDir}/$packageName/$pluginName")
    if ($pluginEntry.Count -ne 1) { throw 'The last catalog version must list the installed AUF2 once.' }

    # Hash the same AUF2 bytes that will go into the ZIP.
    Copy-Item -LiteralPath $pluginPath -Destination $tempPlugin
    $hashOutput = & $XxhsumPath -H128 --tag $tempPlugin
    if ($LASTEXITCODE -ne 0 -or ($hashOutput -join "`n") -notmatch ' = ([0-9a-f]{32})\s*\z') {
        throw 'Could not calculate the AUF2 XXH3-128 hash.'
    }
    $hash = $Matches[1].ToLowerInvariant()

    $packageFiles = [ordered]@{
        $pluginName = $tempPlugin
        'README.md' = Join-Path $PSScriptRoot 'README.md'
        'LICENSE' = Join-Path $projectDir 'LICENSE'
        'THIRD_PARTY_NOTICES.md' = $tempNotices
        'ThirdParty/LICENSE.AviUtl2-SDK.txt' = Join-Path $projectDir 'ThirdParty\LICENSE.AviUtl2-SDK.txt'
    }
    # 開発用と配布用で同じライセンス配置を使用する。
    $notices = [IO.File]::ReadAllText((Join-Path $projectDir 'THIRD_PARTY_NOTICES.md'))
    [IO.File]::WriteAllText($tempNotices, $notices, [Text.UTF8Encoding]::new($false))
    foreach ($file in $packageFiles.Values) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Package file not found: $file" }
    }
    $zip = [IO.Compression.ZipFile]::Open($tempZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $packageFiles.GetEnumerator()) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.Value, "$packageName/$($file.Key)", [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally { $zip.Dispose() }

    if ([IO.File]::ReadAllText($catalogPath) -cne $catalogSource) {
        throw 'Catalog changed during packaging. Run the batch again.'
    }
    if ($pluginEntry[0].XXH3_128 -cne $hash) {
        $pluginEntry[0].XXH3_128 = $hash
        $json = ConvertTo-Json -InputObject $catalog -Depth 12
        [IO.File]::WriteAllText($tempCatalog, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($tempCatalog, $catalogPath, $catalogBackup)
    }
    try {
        if ([IO.File]::Exists($zipPath)) { [IO.File]::Replace($tempZip, $zipPath, [NullString]::Value) }
        else { [IO.File]::Move($tempZip, $zipPath) }
    }
    catch {
        if ([IO.File]::Exists($catalogBackup)) {
            [IO.File]::Replace($catalogBackup, $catalogPath, [NullString]::Value)
        }
        throw
    }
    if ([IO.File]::Exists($catalogBackup)) { [IO.File]::Delete($catalogBackup) }
}
finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    $lock.Dispose()
    foreach ($tempPath in @($tempPlugin, $tempZip, $tempCatalog, $tempNotices)) {
        [IO.File]::Delete($tempPath)
    }
}

Write-Output "Created $zipPath"
Write-Output "Catalog $catalogPath ($($version.version), XXH3_128=$hash)"
