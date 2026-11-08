<#
.SYNOPSIS
  Compare the Permission Sets and Permission Set Groups assigned to two Salesforce users.

.DESCRIPTION
  Queries PermissionSetAssignment for both users via the sf CLI, ignores the
  profile-owned row, splits results into Permission Set Groups and directly
  assigned Permission Sets, prints a comparison, and saves the lists plus a
  comparison.txt to an output folder.

  Requires: Salesforce CLI (sf) with the org already authenticated.

.EXAMPLE
  .\Compare-UserPerms.ps1 -Org basfplay -UserA "SE Test" -UserB "Giuseppe Allegretta"

.EXAMPLE
  .\Compare-UserPerms.ps1 -Org mytso -UserA "Model User" -UserB "New Person" -OutFolder "C:\PermCompare"
#>
param(
    [Parameter(Mandatory = $true)]  [string] $Org,
    [Parameter(Mandatory = $true)]  [string] $UserA,
    [Parameter(Mandatory = $true)]  [string] $UserB,
    [Parameter(Mandatory = $false)] [string] $OutFolder = "C:\PermissionCompare"
)

$ErrorActionPreference = "Stop"

# Make sure sf is available
if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    Write-Error "Salesforce CLI (sf) was not found on this machine."
    return
}

New-Item -ItemType Directory -Path $OutFolder -Force | Out-Null

function Get-UserPerms {
    param([string] $OrgAlias, [string] $UserName)

    $safeName = $UserName -replace "'", "\'"
    $soql = "SELECT PermissionSet.Name, PermissionSet.IsOwnedByProfile, PermissionSetGroup.DeveloperName " +
            "FROM PermissionSetAssignment WHERE Assignee.Name = '$safeName'"

    $raw = sf data query -o $OrgAlias -q $soql --json
    $json = $raw | ConvertFrom-Json
    if ($json.status -ne 0) { throw "Query failed for '$UserName': $($json.message)" }

    $rows = $json.result.records
    $groups = @($rows | Where-Object { $_.PermissionSetGroup } |
                ForEach-Object { $_.PermissionSetGroup.DeveloperName } | Sort-Object -Unique)
    $sets   = @($rows | Where-Object { -not $_.PermissionSetGroup -and -not $_.PermissionSet.IsOwnedByProfile } |
                ForEach-Object { $_.PermissionSet.Name } | Sort-Object -Unique)

    return @{ Groups = $groups; Sets = $sets; RowCount = $rows.Count }
}

function Write-UserList {
    param([string] $UserName, [hashtable] $Perms, [string] $Folder)
    $tag  = $UserName -replace '[^A-Za-z0-9]', '_'
    $text = "User: $UserName`n`nPermission Set Groups ($($Perms.Groups.Count)):`n" + ($Perms.Groups -join "`n") +
            "`n`nPermission Sets ($($Perms.Sets.Count)):`n" + ($Perms.Sets -join "`n")
    Set-Content -Path (Join-Path $Folder "$tag`_assignments.txt") -Value $text
}

# ---- Lookups ----
Write-Host "Org: $Org" -ForegroundColor Cyan
$permsA = Get-UserPerms -OrgAlias $Org -UserName $UserA
if ($permsA.RowCount -eq 0) { Write-Warning "No assignments found for '$UserA' — check the exact user name." }
$permsB = Get-UserPerms -OrgAlias $Org -UserName $UserB
if ($permsB.RowCount -eq 0) { Write-Warning "No assignments found for '$UserB' — check the exact user name." }

Write-UserList -UserName $UserA -Perms $permsA -Folder $OutFolder
Write-UserList -UserName $UserB -Perms $permsB -Folder $OutFolder

# ---- Comparison ----
$out = @()
$out += "Org: $Org"
$out += "Compared: $UserA  vs  $UserB"
$out += "Run: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$out += ""

foreach ($kind in "Groups", "Sets") {
    $label = if ($kind -eq "Groups") { "PERMISSION SET GROUPS" } else { "PERMISSION SETS" }
    $la = @($permsA.$kind); $lb = @($permsB.$kind)
    $both  = @($la | Where-Object { $lb -contains $_ })
    $onlyA = @($la | Where-Object { $lb -notcontains $_ })
    $onlyB = @($lb | Where-Object { $la -notcontains $_ })

    $out += "=== $label ==="
    $out += "Both have ($($both.Count)):";    $out += ($both  | ForEach-Object { "  $_" })
    $out += "Only $UserA ($($onlyA.Count)):"; $out += ($onlyA | ForEach-Object { "  $_" })
    $out += "Only $UserB ($($onlyB.Count)):"; $out += ($onlyB | ForEach-Object { "  $_" })
    $out += ""
}

$comparisonPath = Join-Path $OutFolder "comparison.txt"
Set-Content -Path $comparisonPath -Value ($out -join "`n")

$out | ForEach-Object { $_ }
Write-Host "Saved to $OutFolder (comparison.txt plus one list per user)" -ForegroundColor Green
