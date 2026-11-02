# B&R Next post-restore scripts (ComplianceQuest)

Anonymous Apex scripts to run after a Salesforce Backup and Restore (B&R Next) restore of CQ records.
B&R restores deleted records with new Ids and relinks real lookups, but not Ids stored in text fields
or images in rich text fields. These scripts fix what it leaves behind.

Run each in Developer Console > Debug > Open Execute Anonymous Window, with "Open Log" ticked,
then tick "Debug Only" in the log. Always run with `DRY_RUN = true` first, check the output,
then set `DRY_RUN = false` and run again.

| Order | Script | Fixes | Tested |
|---|---|---|---|
| 1 | `relink_primary_content.apex` | Controlled Document Primary Content (`Content_Reference__c`, text) still holds the deleted file's Id. Sets it to the restored file linked to the document. | Passed 11/2/2026 (Activities 171, 179) |
| 2 | `relink_source_id.apex` | Source Id / Source Name text fields on Investigation, Action, Effectiveness Review and Finding Response still point to the deleted parent (e.g. old complaint number). Copies the relinked lookup's Id and Name. | Passed 11/2/2026 (INV-0000000073, Activity 180) |
| 3 | `reembed_rich_text_images.apex` | Rich text images come back as "Image Not Available". Re-embeds the image files attached to the same record, matched by order. Needs the image attached as a file as well as embedded. | Passed 11/2/2026 (NC-000160) |

Settings at the top of each script:
- `DRY_RUN`: `true` lists what would change; `false` makes the changes.
- `RESTORED_SINCE` (scripts 2 and 3): the restore date in UTC; only records created since then are checked.
- `ONLY_RECORD_ID` (script 3): set to one record Id to test on that record only.
- `TARGETS` (script 3): objects and rich text fields to check; add a line per object.

Notes:
- The Controlled Document must be restored together with its file in the same restore (depth 1),
  after the Recycle Bin is purged; script 1 cannot fix a document whose file was not restored.
- Anything a script cannot match safely is reported as `CHECK BY HAND` and left unchanged.
