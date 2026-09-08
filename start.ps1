$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$flutterPath = Join-Path $PSScriptRoot '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterPath)) {
    $flutterPath = (Get-Command flutter -ErrorAction Stop).Source
}
$runArguments = @('run', '-d', 'windows')
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.env')) {
    $runArguments += '--dart-define-from-file=.env'
}
# Always use the real catalog. The provider itself comes from .env (TVmaze by default).
$runArguments += '--dart-define=DEMO=false'
& $flutterPath @runArguments
exit $LASTEXITCODE
