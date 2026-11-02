// Relink Source Id / Source Name after a B&R restore.
// CQ stores a record's source (the Complaint, NC, CAPA... it came from) in two TEXT fields,
// Source_Id__c and Source_Name__c. B&R relinks real lookups but not text, so after a restore
// these still hold the deleted parent's old Id and number (e.g. Investigation shows COM-0000000019).
//
// For each restored record whose Source Id points to a record that no longer exists, the script
// finds the record's lookup to the same kind of object (e.g. Complaint lookup for a complaint
// source), which B&R did relink, and copies that Id and Name into Source Id / Source Name.
// If there is no such lookup, or more than one with different values, it reports CHECK BY HAND.
//
// Run in Developer Console > Debug > Open Execute Anonymous Window, with "Open Log" ticked,
// then tick "Debug Only" in the log. Run with DRY_RUN = true first, then DRY_RUN = false.

Boolean DRY_RUN = true;
Datetime RESTORED_SINCE = Datetime.newInstanceGmt(2026, 11, 2, 0, 0, 0);  // restore date (UTC)

// CQ objects that have a Source Id text field
List<String> OBJECTS = new List<String>{
    'compliancequest__SQX_Investigation__c',
    'compliancequest__SQX_Action__c',
    'compliancequest__SQX_Effectiveness_Review__c',
    'compliancequest__SQX_Finding_Response__c'
};
String SRC_ID_FIELD = 'compliancequest__Source_Id__c';
String SRC_NAME_FIELD = 'compliancequest__Source_Name__c';

Integer fixedCount = 0;
Integer handCount = 0;
Map<String, Schema.SObjectType> globalTypes = Schema.getGlobalDescribe();

for (String objName : OBJECTS) {
    Map<String, Schema.SObjectField> fieldMap = globalTypes.get(objName).getDescribe().fields.getMap();
    Boolean hasSrcName = fieldMap.containsKey(SRC_NAME_FIELD);

    // Custom lookup fields on this object, with the object each one points to
    Map<String, List<String>> lookupTargets = new Map<String, List<String>>();
    for (Schema.SObjectField sf : fieldMap.values()) {
        Schema.DescribeFieldResult fd = sf.getDescribe();
        if (fd.getType() == Schema.DisplayType.REFERENCE && fd.isCustom()) {
            List<String> targets = new List<String>();
            for (Schema.SObjectType rt : fd.getReferenceTo()) targets.add(rt.getDescribe().getName());
            lookupTargets.put(fd.getName(), targets);
        }
    }

    String soql = 'SELECT Id, Name, ' + SRC_ID_FIELD
                + (hasSrcName ? ', ' + SRC_NAME_FIELD : '')
                + (lookupTargets.isEmpty() ? '' : ', ' + String.join(new List<String>(lookupTargets.keySet()), ', '))
                + ' FROM ' + objName
                + ' WHERE CreatedDate >= :RESTORED_SINCE AND ' + SRC_ID_FIELD + ' != null';
    List<SObject> recs = Database.query(soql);
    if (recs.isEmpty()) { System.debug(objName + ': no restored records with a Source Id'); continue; }

    // 1. Group the Source Ids by object type and find which still exist
    Map<String, Set<Id>> srcIdsByType = new Map<String, Set<Id>>();
    for (SObject r : recs) {
        Id sid;
        try { sid = Id.valueOf((String) r.get(SRC_ID_FIELD)); } catch (Exception e) { continue; }
        String typeName = sid.getSObjectType().getDescribe().getName();
        if (!srcIdsByType.containsKey(typeName)) srcIdsByType.put(typeName, new Set<Id>());
        srcIdsByType.get(typeName).add(sid);
    }
    Set<Id> stillThere = new Set<Id>();
    for (String typeName : srcIdsByType.keySet()) {
        Set<Id> checkIds = srcIdsByType.get(typeName);
        for (SObject s : Database.query('SELECT Id FROM ' + typeName + ' WHERE Id IN :checkIds')) stillThere.add(s.Id);
    }

    // 2. For each broken record, take the lookup that points to the same kind of object
    Map<Id, Id> newSourceByRecord = new Map<Id, Id>();
    Map<String, Set<Id>> newIdsByType = new Map<String, Set<Id>>();
    Map<Id, SObject> brokenRecs = new Map<Id, SObject>();
    for (SObject r : recs) {
        Id sid;
        try { sid = Id.valueOf((String) r.get(SRC_ID_FIELD)); } catch (Exception e) { continue; }
        if (stillThere.contains(sid)) continue;
        String typeName = sid.getSObjectType().getDescribe().getName();
        Set<Id> candidates = new Set<Id>();
        for (String lf : lookupTargets.keySet()) {
            if (lookupTargets.get(lf).contains(typeName) && r.get(lf) != null) candidates.add((Id) r.get(lf));
        }
        String label = objName + ' ' + r.get('Name') + ' (' + r.Id + ')';
        if (candidates.size() != 1) {
            System.debug('CHECK BY HAND: ' + label + ' Source Id ' + sid + ' (' + typeName + ') no longer exists; '
                         + candidates.size() + ' matching lookup value(s) found');
            handCount++;
            continue;
        }
        Id newId = new List<Id>(candidates)[0];
        newSourceByRecord.put(r.Id, newId);
        brokenRecs.put(r.Id, r);
        if (!newIdsByType.containsKey(typeName)) newIdsByType.put(typeName, new Set<Id>());
        newIdsByType.get(typeName).add(newId);
    }

    // 3. Names of the new source records
    Map<Id, String> newNames = new Map<Id, String>();
    for (String typeName : newIdsByType.keySet()) {
        Set<Id> nameIds = newIdsByType.get(typeName);
        for (SObject s : Database.query('SELECT Id, Name FROM ' + typeName + ' WHERE Id IN :nameIds')) {
            newNames.put(s.Id, (String) s.get('Name'));
        }
    }

    // 4. Update
    List<SObject> toUpdate = new List<SObject>();
    for (Id recId : newSourceByRecord.keySet()) {
        SObject r = brokenRecs.get(recId);
        Id newId = newSourceByRecord.get(recId);
        System.debug((DRY_RUN ? 'WOULD RELINK: ' : 'RELINK: ') + objName + ' ' + r.get('Name')
                     + ' source ' + (hasSrcName ? r.get(SRC_NAME_FIELD) : r.get(SRC_ID_FIELD))
                     + ' -> ' + newNames.get(newId) + ' (' + newId + ')');
        SObject upd = r.getSObjectType().newSObject(recId);
        upd.put(SRC_ID_FIELD, String.valueOf(newId));
        if (hasSrcName) upd.put(SRC_NAME_FIELD, newNames.get(newId));
        toUpdate.add(upd);
    }
    if (!DRY_RUN && !toUpdate.isEmpty()) update toUpdate;
    fixedCount += toUpdate.size();
}
System.debug(fixedCount + ' record(s) ' + (DRY_RUN ? 'to relink' : 'relinked') + ', ' + handCount + ' to check by hand. DRY_RUN = ' + DRY_RUN);
