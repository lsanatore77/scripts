<#
Copy Hazard or Control icon files from a source org to a target org.
Uses the sf CLI for every call, so no tokens are handled by the script.

Usage (from the folder containing this script):
    .\hazard_icons.ps1 -Source master -Target basfplay            # download icons + build CSVs only (read-only)
    .\hazard_icons.ps1 -Source master -Target basfplay -Upload    # ...and also upload the icons into the target
                                                                  #    and set cqext__Icon__c on each record
    .\hazard_icons.ps1 -Source master -Target basfplay -Object Control [-Upload]   # same for Controls

Requires: sf CLI logged in to both orgs (sf org list).
Outputs:
  icons-hazard\ or icons-control\     the downloaded image files
  <object>_contentversion_insert.csv   Data Loader Insert on ContentVersion (if you prefer Data Loader)
  <object>_icon_update_template.csv    for the follow-up Icon field update (if you prefer Data Loader)
#>
param(
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [string]$Target,
    [ValidateSet("Hazard", "Control")] [string]$Object = "Hazard",
    [switch]$Upload
)

$ErrorActionPreference = "Stop"
switch ($Object) {
    "Hazard"  { $HazardObj = "cqext__SQX_Hazard__c";  $NameField = "cqext__Hazard_Name__c" }
    "Control" { $HazardObj = "cqext__SQX_Control__c"; $NameField = "cqext__Control_Name__c" }
}
$IconField = "cqext__Icon__c"
$IconDir   = Join-Path $PSScriptRoot "icons-$($Object.ToLower())"
$ApiVer    = "v62.0"
Write-Host "Object: $Object ($HazardObj)"

function Invoke-Soql($org, $query) {
    $json = sf data query --query $query --target-org $org --json | ConvertFrom-Json
    if ($json.status -ne 0) { throw "Query failed on '$org': $($json.message)" }
    return @($json.result.records)
}

function Invoke-Rest($org, $path, $method = "GET", $bodyFile = $null, $outFile = $null) {
    $args = @("api", "request", "rest", $path, "--target-org", $org, "--method", $method)
    if ($bodyFile) { $args += @("--body", "@$bodyFile", "--header", "Content-Type: application/json") }
    if ($outFile)  { $args += @("--stream-to-file", $outFile) }
    $out = & sf @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sf api request failed ($method $path): $out" }
    return $out
}

# ---------- 1. Source hazards and their icon files ----------
$srcHaz = Invoke-Soql $Source "SELECT Id, Name, $NameField, $IconField FROM $HazardObj"
Write-Host "Source $($Object)s: $($srcHaz.Count)"

$ids = ($srcHaz | ForEach-Object { "'$($_.Id)'" }) -join ","
$links = Invoke-Soql $Source "SELECT LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN ($ids)"
$hazToDoc = @{}
foreach ($l in $links) { if (-not $hazToDoc.ContainsKey($l.LinkedEntityId)) { $hazToDoc[$l.LinkedEntityId] = $l.ContentDocumentId } }

$docIds = ($hazToDoc.Values | Select-Object -Unique | ForEach-Object { "'$_'" }) -join ","
$versions = Invoke-Soql $Source "SELECT Id, Title, PathOnClient, ContentDocumentId FROM ContentVersion WHERE IsLatest = true AND ContentDocumentId IN ($docIds)"
$docToVer = @{}
foreach ($v in $versions) { $docToVer[$v.ContentDocumentId] = $v }
Write-Host "Icon files found: $($docToVer.Count)"

# ---------- 2. Download icons ----------
New-Item -ItemType Directory -Path $IconDir -Force | Out-Null
foreach ($v in $versions) {
    $fname = Split-Path $v.PathOnClient -Leaf
    $dest  = Join-Path $IconDir $fname
    if (Test-Path $dest) { Write-Host "  exists  $fname"; continue }
    Invoke-Rest $Source "/services/data/$ApiVer/sobjects/ContentVersion/$($v.Id)/VersionData" "GET" $null $dest | Out-Null
    Write-Host "  saved   $fname ($((Get-Item $dest).Length) bytes)"
}

# ---------- 3. Target hazards, matched on Hazard Name ----------
$tgtHaz = Invoke-Soql $Target "SELECT Id, $NameField, $IconField FROM $HazardObj"
$tgtByName = @{}
foreach ($h in $tgtHaz) { if ($h.$NameField) { $tgtByName[$h.$NameField.Trim().ToLower()] = $h } }
Write-Host "Target $($Object)s: $($tgtHaz.Count)"

# Icon IDs that point at a file that really exists in the target (copied-over IDs from the source won't)
$validIcons = @{}
$iconIds = @($tgtHaz | Where-Object { $_.$IconField } | ForEach-Object { "'$($_.$IconField)'" })
if ($iconIds.Count) {
    $existing = Invoke-Soql $Target "SELECT Id FROM ContentDocument WHERE Id IN ($($iconIds -join ','))"
    foreach ($e in $existing) { $validIcons[$e.Id] = $true }
}

# ---------- 4. Build the work list and CSVs ----------
$work = @(); $skipped = @()
foreach ($h in $srcHaz) {
    $name = ("" + $h.$NameField).Trim()
    $doc  = $hazToDoc[$h.Id]
    $ver  = if ($doc) { $docToVer[$doc] } else { $null }
    $tgt  = $tgtByName[$name.ToLower()]
    if (-not $ver) { $skipped += "$name : no icon file in source"; continue }
    if (-not $tgt) { $skipped += "$name : no matching $Object in target"; continue }
    $fname = Split-Path $ver.PathOnClient -Leaf
    $work += [pscustomobject]@{
        HazardName   = $name
        Title        = $ver.Title
        PathOnClient = $fname
        LocalPath    = (Join-Path $IconDir $fname)
        TargetId     = $tgt.Id
        TargetIcon   = $tgt.$IconField
        SourceDoc    = $doc
    }
}

$work | Select-Object Title, PathOnClient, @{n="VersionData";e={$_.LocalPath}}, @{n="FirstPublishLocationId";e={$_.TargetId}} |
    Export-Csv -Path (Join-Path $PSScriptRoot "$($Object.ToLower())_contentversion_insert.csv") -NoTypeInformation -Encoding UTF8
$work | Select-Object @{n="Id";e={$_.TargetId}}, HazardName, @{n="SourceContentDocumentId";e={$_.SourceDoc}}, @{n=$IconField;e={""}} |
    Export-Csv -Path (Join-Path $PSScriptRoot "$($Object.ToLower())_icon_update_template.csv") -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Ready to load: $($work.Count) $($Object)s  (CSVs written next to the script)"
if ($skipped.Count) { Write-Host "Skipped:"; $skipped | ForEach-Object { Write-Host "  $_" } }

if (-not $Upload) {
    Write-Host ""
    Write-Host "Read-only run finished. Re-run with -Upload to push the icons into '$Target'."
    exit 0
}

# ---------- 5. Upload into target: create file linked to hazard, then set Icon field ----------
Write-Host ""
Write-Host "Uploading to '$Target'..."
$tmp = Join-Path $env:TEMP "hazard_icon_body.json"
$done = 0
foreach ($w in $work) {
    if ($w.TargetIcon -and $validIcons.ContainsKey($w.TargetIcon)) {
        Write-Host "  skip    $($w.HazardName) (Icon already set to an existing file: $($w.TargetIcon))"; continue
    }

    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($w.LocalPath))
    @{ Title = $w.Title; PathOnClient = $w.PathOnClient; VersionData = $b64; FirstPublishLocationId = $w.TargetId } |
        ConvertTo-Json -Compress | Set-Content -Path $tmp -Encoding UTF8
    $res = Invoke-Rest $Target "/services/data/$ApiVer/sobjects/ContentVersion" "POST" $tmp | ConvertFrom-Json
    $cvId = $res.id

    $cd = Invoke-Soql $Target "SELECT ContentDocumentId FROM ContentVersion WHERE Id = '$cvId'"
    $docId = $cd[0].ContentDocumentId

    @{ $IconField = $docId } | ConvertTo-Json -Compress | Set-Content -Path $tmp -Encoding UTF8
    Invoke-Rest $Target "/services/data/$ApiVer/sobjects/$HazardObj/$($w.TargetId)" "PATCH" $tmp | Out-Null

    Write-Host "  done    $($w.HazardName) -> $docId"
    $done++
}
Remove-Item $tmp -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Uploaded $done icons into '$Target'."
