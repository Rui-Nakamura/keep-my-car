param(
    [string]$JavaExe = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe',
    [string]$GradleCache = "$env:USERPROFILE\.gradle\caches\modules-2\files-2.1"
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
function Find-Jar([string]$Group, [string]$Artifact, [string]$Version) {
    $directory = Join-Path $GradleCache "$Group\$Artifact\$Version"
    $jar = Get-ChildItem -LiteralPath $directory -Recurse -Filter "$Artifact-$Version.jar" | Select-Object -First 1
    if (!$jar) { throw "Existing Kotlin toolchain jar missing: $Artifact $Version. No dependency will be downloaded." }
    return $jar.FullName
}
$stdlib = Find-Jar 'org.jetbrains.kotlin' 'kotlin-stdlib' '2.4.0'
$annotations = Find-Jar 'org.jetbrains' 'annotations' '13.0'
$compilerJars = @(
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-compiler-embeddable' '2.4.0'),
    $stdlib,
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-script-runtime' '2.4.0'),
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-reflect' '1.6.10'),
    (Find-Jar 'org.jetbrains.kotlin' 'kotlin-daemon-embeddable' '2.4.0'),
    (Find-Jar 'org.jetbrains.kotlinx' 'kotlinx-coroutines-core-jvm' '1.8.0'),
    $annotations
)
$outputDirectory = Join-Path $repoRoot 'build\backup_file_probe_checks'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$outputJar = Join-Path $outputDirectory 'checks.jar'
$source = Join-Path $repoRoot 'android\app\src\main\kotlin\dev\keepmycar\prototype\keep_my_car\BackupFileOperation.kt'
$checks = Join-Path $PSScriptRoot 'BackupFileProbeChecks.kt'
# Deliberately guard the current Android wiring without adding a framework/interface.
# A refactor must update and review this guard; mode-less or w must fail closed.
$channelSource = Get-Content -LiteralPath (Join-Path (Split-Path $source) 'BackupFileChannel.kt') -Raw
$outputCalls = [regex]::Matches($channelSource, '\bopenOutputStream\s*\(')
$truncatingSave = [regex]::Matches($channelSource, 'BackupStreamIo\.save\s*\(\s*\{\s*resolver\.openOutputStream\s*\(\s*uri\s*,\s*"wt"\s*\)\s*\}\s*,\s*bytes\s*,\s*operation\.abandoned\s*\)')
if ($outputCalls.Count -ne 1 -or $truncatingSave.Count -ne 1) {
    throw 'Android save must call BackupStreamIo.save with exactly one explicit openOutputStream(uri, "wt"); review wiring changes.'
}
Write-Output 'PASS Android source guard: explicit wt save wiring, no alternate output open'
& $JavaExe -cp ($compilerJars -join ';') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -classpath "$stdlib;$annotations" -jvm-target 17 -d $outputJar $source $checks
if ($LASTEXITCODE -ne 0) { throw 'Kotlin probe compilation failed' }
& $JavaExe -cp "$outputJar;$stdlib" dev.keepmycar.prototype.keep_my_car.BackupFileProbeChecksKt
if ($LASTEXITCODE -ne 0) { throw 'Kotlin probe checks failed' }
