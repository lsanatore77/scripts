# Compare-UserPerms

Compares the Permission Sets and Permission Set Groups assigned to two Salesforce users and reports what they share and where they differ.

Typical use: check that a new workshop or demo user has the same access as a known-good "model" user before handing over an org.

## Requirements

- Windows PowerShell 5.1 or later
- Salesforce CLI (`sf`) installed and authenticated to the org (`sf org list` should show the alias)
- Permission to read `PermissionSetAssignment` in that org (System Administrator is fine)

## Usage

```powershell
.\Compare-UserPerms.ps1 -Org <alias> -UserA "<full name>" -UserB "<full name>"
```

Example:

```powershell
.\Compare-UserPerms.ps1 -Org basfplay -UserA "SE Test" -UserB "Giuseppe Allegretta"
```

| Parameter    | Required | Description |
|--------------|----------|-------------|
| `-Org`       | Yes      | Org alias from `sf org list` (any sandbox, TSO or scratch org you are authenticated to) |
| `-UserA`     | Yes      | Full name of the first user, exactly as shown in Salesforce |
| `-UserB`     | Yes      | Full name of the second user |
| `-OutFolder` | No       | Where to save the output. Defaults to `C:\PermissionCompare` (created if missing) |

## What it does

1. Runs one SOQL query per user against `PermissionSetAssignment` using the `sf` CLI.
2. Ignores the profile-owned row (every user has one; it is not a real assignment).
3. Splits the remaining rows into **Permission Set Groups** (rows with a `PermissionSetGroupId`) and directly assigned **Permission Sets**.
4. Prints a comparison on screen and saves it to disk.

## Output

In the output folder:

- `comparison.txt` — for both groups and sets: what both users have, what only User A has, what only User B has, with counts
- `<UserA>_assignments.txt` — full list for User A
- `<UserB>_assignments.txt` — full list for User B

Names in the list files use API names (`DeveloperName` for groups, `Name` for sets).

## Notes

- Group assignments are reported as the group only; the sets inside a group are not listed separately.
- If a user name is not found the script prints a warning and continues, so a typo shows up as an empty list rather than a wrong answer.
- If PowerShell refuses to run the script the first time, set the execution policy once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
- Related: the **Copy User Permissions** screen flow in the dev sandbox copies the missing assignments from one user to another after showing a preview.
