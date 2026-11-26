param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,

    [int]$BuildNumber = 1
)

$ErrorActionPreference = 'Stop'

flutter build apk --release `
    "--dart-define=API_BASE_URL=$ApiBaseUrl" `
    "--build-number=$BuildNumber"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$apkPath = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-release.apk'
Write-Host "APK created: $([IO.Path]::GetFullPath($apkPath))"
