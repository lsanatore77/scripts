// Loads Sections and Questions into the 3 CQ Form Checklist Drafts in basfplay.
// Run once:  sf apex run --target-org basfplay --file load_checklist_questions.apex
// Safe to re-run: stops without changes if any of the 3 checklists already has sections.
// LOTO and Confined Space questions are copied from master; WFH questions were recovered
// from master's last Working From Heights submission (its checklist AUTO[001] no longer exists).

String RESULT_TYPE = 'Yes/No/NA';

// checklist Name => list of [section title, question 1, question 2, ...]
Map<String, List<List<String>>> data = new Map<String, List<List<String>>>{
    'FRM-CHK-LOTO[001]' => new List<List<String>>{
        new List<String>{ 'Housekeeping',
            'Are walkways free of debris and obstructions?',
            'Is General Housekeeping neat and orderly, Items picked up off the floor?',
            'Are work surfaces clear of clutter?' },
        new List<String>{ 'Fall Protection',
            'Fall Protection',
            'Mezzanine gates closed unless material is being loaded?' },
        new List<String>{ 'Ladders',
            'Ladders are well maintained and in satisfactory condition?',
            'Are team members standing below the first two steps?',
            'Ladders are being used properly and with 3 point contact?' }
    },
    'FRM-CHK-CONFINED-SPACE[001]' => new List<List<String>>{
        new List<String>{ 'General',
            'Is the space large enough for an employee to bodily enter and perform work?',
            'Are there limited means of entry or exit?',
            'Is it NOT designated for continuous occupancy?' },
        new List<String>{ 'Hazard Identifications',
            'Is there a potential for an atmospheric hazard?',
            'Is there a potential for an engulfment hazard?',
            'Is the space so configured that it poses a hazard?' },
        new List<String>{ 'Atmospheric Hazards',
            'Oxygen Deficiency (<19%)?',
            'Flammable Materials?',
            'Toxic Substances?' }
    },
    'FRM-CHK-WFH[001]' => new List<List<String>>{
        new List<String>{ 'Site Preparation',
            'Have the tasks and the associated risks been identified?',
            'Have the employees completed the necessary training?',
            'Appropriate equipment required to complete the task is available and in good condition?' },
        new List<String>{ 'Site Setup',
            'Work Area Secure?',
            'Equipment Secured and Tested?',
            'Are anchor points secure?' },
        new List<String>{ 'Work Phase',
            'Workers are equipped with appropriate PPE',
            'Is equipment usage correct?' }
    }
};

// --- checks ---
List<compliancequest__SQX_Result_Type__c> rts = [SELECT Id FROM compliancequest__SQX_Result_Type__c WHERE Name = :RESULT_TYPE];
if (rts.size() != 1) { throw new IllegalArgumentException('Expected exactly 1 Result Type named ' + RESULT_TYPE + ', found ' + rts.size()); }
Id rtId = rts[0].Id;

Map<String, compliancequest__SQX_Controlled_Document__c> docs = new Map<String, compliancequest__SQX_Controlled_Document__c>();
for (compliancequest__SQX_Controlled_Document__c d : [
        SELECT Id, Name, RecordType.DeveloperName, compliancequest__Document_Status__c
        FROM compliancequest__SQX_Controlled_Document__c WHERE Name IN :data.keySet()]) {
    docs.put(d.Name, d);
}
for (String n : data.keySet()) {
    if (!docs.containsKey(n)) { throw new IllegalArgumentException('Checklist not found: ' + n); }
    compliancequest__SQX_Controlled_Document__c d = docs.get(n);
    if (d.RecordType.DeveloperName != 'CQ_Form_Checklist') { throw new IllegalArgumentException(n + ' is not a CQ Form Checklist'); }
    if (d.compliancequest__Document_Status__c != 'Draft') { System.debug('WARNING: ' + n + ' status is ' + d.compliancequest__Document_Status__c + ', expected Draft'); }
}
Integer existing = [SELECT COUNT() FROM cqext__CQF_Section__c WHERE cqext__SQX_Controlled_Document__c IN :docs.values()];
if (existing > 0) { throw new IllegalArgumentException('Stopped: these checklists already have ' + existing + ' sections. Nothing was changed.'); }

// --- sections ---
List<cqext__CQF_Section__c> sections = new List<cqext__CQF_Section__c>();
List<List<String>> sectionRows = new List<List<String>>();
for (String n : data.keySet()) {
    Integer order = 1;
    for (List<String> row : data.get(n)) {
        sections.add(new cqext__CQF_Section__c(
            cqext__SQX_Controlled_Document__c = docs.get(n).Id,
            cqext__Section_Title__c = row[0],
            cqext__Order__c = order,
            cqext__Analysis_Code__c = String.valueOf(order)));
        sectionRows.add(row);
        order++;
    }
}
insert sections;

// --- questions ---
List<cqext__CQF_Question__c> questions = new List<cqext__CQF_Question__c>();
for (Integer i = 0; i < sections.size(); i++) {
    List<String> row = sectionRows[i];
    for (Integer q = 1; q < row.size(); q++) {
        questions.add(new cqext__CQF_Question__c(
            cqext__CQF_Section__c = sections[i].Id,
            cqext__Question_Title_Long__c = row[q],
            cqext__Order__c = q,
            cqext__Weight__c = 1,
            cqext__Analysis_Code__c = String.valueOf(q),
            cqext__SQX_Result_Type__c = rtId));
    }
}
insert questions;

System.debug('Inserted ' + sections.size() + ' sections (expected 9) and ' + questions.size() + ' questions (expected 25)');
