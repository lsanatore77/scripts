// Relink Primary Content after a B&R restore.
// Finds Controlled Documents whose Primary Content (Content_Reference__c) points to a file
// that no longer exists, and sets it to the restored file linked to that document
// (ContentVersion.Controlled_Document__c). Run in Developer Console > Execute Anonymous.
// DRY_RUN = true only lists what would change.

Boolean DRY_RUN = true;

// 1. Documents with a Primary Content value
Map<Id, compliancequest__SQX_Controlled_Document__c> docs = new Map<Id, compliancequest__SQX_Controlled_Document__c>(
    [SELECT Id, Name, compliancequest__Content_Reference__c
     FROM compliancequest__SQX_Controlled_Document__c
     WHERE compliancequest__Content_Reference__c != null]);

// 2. Which referenced files still exist
Set<Id> refIds = new Set<Id>();
for (compliancequest__SQX_Controlled_Document__c d : docs.values()) {
    refIds.add((Id) d.compliancequest__Content_Reference__c);
}
Set<Id> existing = new Map<Id, ContentDocument>([SELECT Id FROM ContentDocument WHERE Id IN :refIds]).keySet();

// 3. Broken documents only
Map<Id, compliancequest__SQX_Controlled_Document__c> broken = new Map<Id, compliancequest__SQX_Controlled_Document__c>();
for (compliancequest__SQX_Controlled_Document__c d : docs.values()) {
    if (!existing.contains((Id) d.compliancequest__Content_Reference__c)) broken.put(d.Id, d);
}

// 4. Restored files linked to those documents (latest version)
Map<Id, List<ContentVersion>> filesByDoc = new Map<Id, List<ContentVersion>>();
for (ContentVersion cv : [SELECT ContentDocumentId, Title, compliancequest__Controlled_Document__c
                          FROM ContentVersion
                          WHERE IsLatest = true AND compliancequest__Controlled_Document__c IN :broken.keySet()]) {
    Id docId = cv.compliancequest__Controlled_Document__c;
    if (!filesByDoc.containsKey(docId)) filesByDoc.put(docId, new List<ContentVersion>());
    filesByDoc.get(docId).add(cv);
}

// 5. Relink when there is exactly one candidate file; report the rest
List<compliancequest__SQX_Controlled_Document__c> toUpdate = new List<compliancequest__SQX_Controlled_Document__c>();
for (compliancequest__SQX_Controlled_Document__c d : broken.values()) {
    List<ContentVersion> files = filesByDoc.get(d.Id);
    if (files == null) {
        System.debug('NO FILE: ' + d.Name + ' (' + d.Id + ') - re-upload needed');
    } else if (files.size() > 1) {
        System.debug('CHECK BY HAND: ' + d.Name + ' has ' + files.size() + ' files (primary + secondary?)');
    } else {
        System.debug('RELINK: ' + d.Name + ' -> ' + files[0].ContentDocumentId + ' (' + files[0].Title + ')');
        toUpdate.add(new compliancequest__SQX_Controlled_Document__c(
            Id = d.Id, compliancequest__Content_Reference__c = files[0].ContentDocumentId));
    }
}
System.debug(toUpdate.size() + ' document(s) to relink. DRY_RUN = ' + DRY_RUN);
if (!DRY_RUN && !toUpdate.isEmpty()) update toUpdate;
