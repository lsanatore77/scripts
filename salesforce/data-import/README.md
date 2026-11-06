# Data import scripts (ComplianceQuest demo / TSO orgs)

Scripts for copying CQ configuration data from master into a new demo or TSO org.
The full procedure, with gotchas, is in the runbook doc "CQ Config Data Migration Runbook (SFDMU)".

| Script | Does | Tested |
|---|---|---|
| `sfdmu_questions_export.json` | SFDMU config for Impact Assessment questions: CQ Tasks (read-only, matched by Name) → Task Questions (upsert on Task + Name) → Answer Options (insert). Scoped to the 13 Change Order tasks. | Passed 11/4/2026 (master to basfplay: 42 Questions, 76 Answer Options) |
| `set_result_type.apex` | Run after the Questions job: sets the 4 Regulatory Impact questions to the "Yes/No/NA" Result Type (left out of the SFDMU run). | Passed 11/4/2026 (basfplay) |
| `sfdmu_cause_codes_export.json` | SFDMU config for cause codes: Categories (upsert on Name, existing ones left untouched) → Sub-Categories (upsert on Category + Name) → Codes (insert). | Passed 11/4/2026 (master to basfplay: 11 / 45 / 77 inserted) |
| `hazard_icons.ps1` | Copies the icon image on each Hazard or Control from a source org to a target org: downloads the files, creates them on the matching target records (matched by Hazard Name / Control Name) and sets `cqext__Icon__c`. | Passed 11/5/2026 (master to basfplay: 20 Hazards, Controls) |

## SFDMU jobs

Each config goes in its own folder, renamed to `export.json` (SFDMU only reads that exact name). From that folder:

```
sf sfdmu run --sourceusername master --targetusername <target> --simulation --canmodify <target-domain>
sf sfdmu run --sourceusername master --targetusername <target> --canmodify <target-domain>
```

- Always run the simulation first and check the DATA PROCESSING SUMMARY.
- Run the real job **once**: Answer Options and Cause Codes use Insert, so a second run duplicates them.
- `--canmodify` is required for production targets (TSOs, Trialforce orgs), e.g. `basfplay.my.salesforce.com`.
- Cause codes: CQ ships Categories named "Environment" and "Materials"; master uses "Environmental" and "Material".
  Rename them in the target before the run or you get near-duplicate Categories.
- Order: Questions job, then `set_result_type.apex` (Developer Console > Execute Anonymous, or `sf apex run -o <target> -f set_result_type.apex`).

## hazard_icons.ps1

PowerShell; needs only the sf CLI, logged in to both orgs (`sf org list`). No Python, no tokens.

```
.\hazard_icons.ps1 -Source master -Target <target>                            # dry run: download + match, changes nothing
.\hazard_icons.ps1 -Source master -Target <target> -Upload                    # upload Hazard icons
.\hazard_icons.ps1 -Source master -Target <target> -Object Control            # dry run for Controls
.\hazard_icons.ps1 -Source master -Target <target> -Object Control -Upload    # upload Control icons
```

Before running:
- Load the Hazard / Control records into the target first (Data Loader). Leave `cqext__Icon__c` unmapped.
- Names must match exactly between orgs; the HAZ-/CTL- record numbers don't matter.

First run on a machine:
```
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Unblock-File .\hazard_icons.ps1
```
If `sf api request rest` is not found, run `sf update`.

Notes:
- Safe to re-run: records whose Icon already points at a real file in the target are skipped.
  Icon IDs copied over from the source org (not real files in the target) get replaced.
- Images download into `icons-hazard\` / `icons-control\` next to the script.
- Also writes `<object>_contentversion_insert.csv` and `<object>_icon_update_template.csv`
  in case you'd rather do the load with the desktop Data Loader.
- dataloader.io can't do this: it exports `VersionData` as a URL, not the image, and can't upload files.
