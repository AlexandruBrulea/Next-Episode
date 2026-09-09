param([string]$EnvFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envText = Get-Content -LiteralPath $EnvFile -Raw
$contactEmail = ''
if ($envText.TrimStart().StartsWith('{')) {
    $contactEmail = [string](($envText | ConvertFrom-Json).SUPPORT_EMAIL)
} else {
    foreach ($line in ($envText -split "`n")) {
        if ($line -match '^\s*SUPPORT_EMAIL\s*=\s*(.*?)\s*$') {
            $contactEmail = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
}
if ($contactEmail -notmatch '^[^\s@<>"'':;]+@[^\s@<>"'':;]+\.[^\s@<>"'':;]+$') {
    throw 'Set a valid SUPPORT_EMAIL in the selected env file before exporting legal documents.'
}
$outputRoot = Join-Path $projectRoot 'docs/legal'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
foreach ($name in @('privacy', 'terms', 'support')) {
    if ($name -eq 'support') {
        $document = [pscustomobject]@{
            updated = ''
            sections = @(
                [pscustomobject]@{
                    title = 'Contact support'
                    body = 'For help with Next Episode, feedback or privacy requests, email {{SUPPORT_EMAIL}}. Support is provided by Alexandru Ionut Brulea, Romania.'
                    links = @([pscustomobject]@{ label = '{{SUPPORT_EMAIL}}'; url = 'mailto:{{SUPPORT_EMAIL}}' })
                },
                [pscustomobject]@{
                    title = 'Reporting a problem'
                    body = 'Include your app version (Settings → Version), device model, operating system version and the steps that led to the problem. Screenshots are optional. Please remove private information and never send passwords or API keys.'
                    links = @()
                },
                [pscustomobject]@{
                    title = 'Your library and progress'
                    body = 'Your library and watch progress are stored on your device. Support cannot access or restore that local database. For storage, deletion and external-service details, read the Privacy Policy.'
                    links = @([pscustomobject]@{ label = 'Privacy Policy'; url = 'privacy.html' })
                }
            )
        }
    } else {
        $document = Get-Content -LiteralPath (Join-Path $projectRoot "assets/legal/$name.json") -Raw | ConvertFrom-Json
    }
    foreach ($section in $document.sections) {
        $section.body = $section.body.Replace('{{SUPPORT_EMAIL}}', $contactEmail)
        foreach ($link in $section.links) {
            $link.url = $link.url.Replace('{{SUPPORT_EMAIL}}', $contactEmail)
            $link.label = $link.label.Replace('{{SUPPORT_EMAIL}}', $contactEmail)
        }
    }
    $title = switch ($name) { 'privacy' { 'Privacy Policy' } 'terms' { 'Terms of Use' } 'support' { 'Support' } }
    $updatedLine = if ($document.updated) { '<small>Last updated: ' + [System.Net.WebUtility]::HtmlEncode($document.updated) + '</small>' } else { '' }
    $body = foreach ($section in $document.sections) {
        '<section><h2>' + [System.Net.WebUtility]::HtmlEncode($section.title) + '</h2>'
        foreach ($paragraph in ($section.body -split "`n`n")) {
            '<p>' + [System.Net.WebUtility]::HtmlEncode($paragraph) + '</p>'
        }
        foreach ($link in $section.links) {
            '<p><a href="' + [System.Net.WebUtility]::HtmlEncode($link.url) + '">' + [System.Net.WebUtility]::HtmlEncode($link.label) + '</a></p>'
        }
        '</section>'
    }
    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title | Next Episode</title>
<style>body{margin:0;background:#111827;color:#e5e7eb;font:17px/1.7 system-ui,sans-serif}main{max-width:760px;margin:auto;padding:40px 24px 80px}h1{font-size:2.2rem;line-height:1.2}h2{font-size:1.2rem;margin-top:2rem;color:#fff}a{color:#7de2df;overflow-wrap:anywhere}nav{display:flex;flex-wrap:wrap;gap:24px}small{color:#bac3d4}a:focus-visible{outline:2px solid #7de2df;outline-offset:4px}</style></head>
<body><main><nav aria-label="Support and legal documents"><a href="support.html">Support</a><a href="privacy.html">Privacy Policy</a><a href="terms.html">Terms of Use</a></nav>
<p>Next Episode</p><h1>$title</h1>$updatedLine
$($body -join "`n")
</main></body></html>
"@
    [IO.File]::WriteAllText((Join-Path $outputRoot "$name.html"), $html)
    Write-Output "Exported docs/legal/$name.html"
}
