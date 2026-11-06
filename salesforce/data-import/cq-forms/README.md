# CQ Forms (master to a new org)

Form designs and checklist questions for four CQ Forms, moved master to basfplay on 11/5/2026.

| File | What it is |
|---|---|
| `Atmospheric_Testing_Form.cqf-json` | Form design. Primary object Safety Assessment; detail stays inside the form. |
| `LOTO.cqf-json` | FLHA - LOTO form design. Primary object Safety Inspection, context Permit; questions come from checklist `FRM-CHK-LOTO[001]`. |
| `Confined_Space.cqf-json` | FLHA - Confined Space form design; questions from `FRM-CHK-CONFINED-SPACE[001]`. |
| `Working_From_Heights.cqf-json` | FLHA - Working From Heights form design; questions from `FRM-CHK-WFH[001]`. |
| `load_checklist_questions.apex` | Loads the Sections and Questions into the 3 checklist documents (9 sections, 25 questions). |

The `.cqf-json` files hold no record IDs, only object and field API names, so they work in any org with the same CQ objects.

## Order

1. Check the target has `cqext__SQX_Safety_Inspection__c`, `cqext__SQX_Safety_Assessment__c`, the CQ Form record types,
   and a Result Type named **Yes/No/NA** (it comes over with the Impact Assessment job).
2. Create the 3 checklist Controlled Documents (record type CQ Form Checklist) in **Draft**, named exactly
   `FRM-CHK-LOTO[001]`, `FRM-CHK-CONFINED-SPACE[001]`, `FRM-CHK-WFH[001]`.
3. Load their questions:
   ```
   sf apex run --target-org <target> --file load_checklist_questions.apex
   ```
   Expect "Inserted 9 sections (expected 9) and 25 questions (expected 25)". Safe to re-run: it stops without
   changes if any of the 3 checklists already has sections.
4. Create each CQ Form Controlled Document and check in its `.cqf-json`.
5. Approve and release the checklists and the forms.

Notes:
- The Working From Heights questions were recovered from master's last WFH submission; its original checklist (AUTO[001]) no longer exists in master.
- If the checklist names differ in the target, edit the three names at the top of the Apex before running.
