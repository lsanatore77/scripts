# User provisioning scripts (ComplianceQuest demo / TSO orgs)

Anonymous Apex to copy one template user's access to a list of other users.
Everything is found by username, nothing by Id, so the same script works in any org.

Run in Developer Console > Debug > Open Execute Anonymous Window, with "Open Log" ticked,
then tick "Debug Only" in the log and read the lines starting with `RESULT`.

| Script | Does | Tested |
|---|---|---|
| `clone_user_permissions.apex` | Copies the template user's permission set groups, standalone permission sets and managed package licenses (e.g. compliancequest, cqext) to each target user. Only adds what a target is missing, so it is safe to re-run. | Passed 11/2/2026 (cqworkshop, 16 users); package licenses 11/3/2026 (basfplay, 24 users) |

Settings at the top of the script:
- `templateUsername`: the user whose access gets copied. Set this user up fully first (PSGs, sets, package licenses).
- `targetUsernames`: the users to copy to, one per line in quotes. They must already exist.

Notes:
- Users have to be created first (Workbench > data > Insert > User; dataloader.io blocks the User object).
- Permission sets that come through a group are not copied separately; the group brings them.
- A row that fails (license mismatch, no package seats left) is reported per user and the rest still load.
- Queues, public groups, roles and Personnel records are not copied.
