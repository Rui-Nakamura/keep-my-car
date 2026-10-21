# Independent external fixtures: .NET ZIP/SHA implementations, never app codecs.
# Run from any cwd using PowerShell 7. Generated ZIPs are checked into the repo.
$ErrorActionPreference = 'Stop'
$planBytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'zip_v1_plan.json'))
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($planBytes)).ToLowerInvariant()
$manifest = [ordered]@{
  format = 'keep-my-car-zip-backup'
  formatVersion = 1
  planSchemaVersion = 1
  hasPhoto = $false
  files = @{ 'plan.json' = @{ sizeBytes = $planBytes.Length; sha256 = $hash } }
} | ConvertTo-Json -Depth 4 -Compress
$manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes($manifest)
foreach ($profile in @('stored', 'deflate')) {
  $level = if ($profile -eq 'stored') { [IO.Compression.CompressionLevel]::NoCompression } else { [IO.Compression.CompressionLevel]::Optimal }
  $output = [IO.MemoryStream]::new()
  $zip = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $true)
  foreach ($file in @(@('manifest.json', $manifestBytes), @('plan.json', $planBytes))) {
    $entry = $zip.CreateEntry($file[0], $level)
    $entry.LastWriteTime = [DateTimeOffset]::new(2026, 10, 1, 0, 0, 0, [TimeSpan]::Zero)
    $stream = $entry.Open()
    try { $stream.Write($file[1], 0, $file[1].Length) } finally { $stream.Dispose() }
  }
  $zip.Dispose()
  [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot "zip_v1_$profile.zip"), $output.ToArray())
  $output.Dispose()
}
