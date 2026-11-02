// Re-embed rich text images after a B&R restore.
// B&R restores the record but its rich text images come back as "Image Not Available".
// This script finds those broken images in the fields listed below and replaces them with
// the image files attached to the same record (the process rule: attach every important
// image as a file as well as embedding it).
//
// Matching: the restore wipes the original image name, so images are matched by order.
//   - Broken images, in the order they appear in the field(s), get the record's attached
//     image files in the order they were uploaded (oldest first).
//   - Only when the number of broken images equals the number of attached image files.
//     Otherwise the record is reported as CHECK BY HAND and left alone.
//
// Run in Developer Console > Debug > Open Execute Anonymous Window, with "Open Log" ticked.
// Run with DRY_RUN = true first; it only lists what would change. Then set DRY_RUN = false.
// Each run handles up to MAX_RECORDS records; run again until it reports 0 to fix.

Boolean DRY_RUN = true;
Datetime RESTORED_SINCE = Datetime.newInstanceGmt(2026, 11, 2, 0, 0, 0);  // restore date (UTC)
Integer MAX_RECORDS = 25;
Id ONLY_RECORD_ID = null;  // set to one record Id to test on that record only
Integer MAX_IMAGE_BYTES = 1000000;  // Salesforce limit for one rich text image (about 1 MB)

// Object API name -> rich text fields to check
Map<String, List<String>> TARGETS = new Map<String, List<String>>{
    'compliancequest__SQX_Nonconformance__c' => new List<String>{ 'compliancequest__Description_RT__c' }
};

Pattern BROKEN_IMG = Pattern.compile('<img[^>]*rte_broken_image[^>]*>(</img>)?');
Set<String> IMAGE_TYPES = new Set<String>{ 'png', 'jpg', 'jpeg', 'gif' };
Integer fixedCount = 0;
Integer handCount = 0;

for (String objName : TARGETS.keySet()) {
    List<String> fields = TARGETS.get(objName);
    String soql = 'SELECT Id, Name, ' + String.join(fields, ', ') + ' FROM ' + objName
                + ' WHERE CreatedDate >= :RESTORED_SINCE'
                + (ONLY_RECORD_ID != null ? ' AND Id = :ONLY_RECORD_ID' : '')
                + ' ORDER BY CreatedDate';

    // 1. Records with at least one broken image (long text fields can't be filtered in SOQL)
    Map<Id, SObject> broken = new Map<Id, SObject>();
    Map<Id, Integer> brokenCount = new Map<Id, Integer>();
    for (SObject rec : Database.query(soql)) {
        Integer n = 0;
        for (String f : fields) {
            String html = (String) rec.get(f);
            if (html == null) continue;
            Matcher m = BROKEN_IMG.matcher(html);
            while (m.find()) n++;
        }
        if (n > 0) { broken.put(rec.Id, rec); brokenCount.put(rec.Id, n); }
        if (broken.size() >= MAX_RECORDS) break;
    }
    if (broken.isEmpty()) { System.debug(objName + ': no broken images found'); continue; }

    // 2. Image files attached to those records, oldest first
    Map<Id, Id> docToRecord = new Map<Id, Id>();
    for (ContentDocumentLink l : [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink
                                  WHERE LinkedEntityId IN :broken.keySet()]) {
        docToRecord.put(l.ContentDocumentId, l.LinkedEntityId);
    }
    Map<Id, List<ContentVersion>> filesByRecord = new Map<Id, List<ContentVersion>>();
    for (ContentVersion cv : [SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize
                              FROM ContentVersion
                              WHERE IsLatest = true AND ContentDocumentId IN :docToRecord.keySet()
                              ORDER BY ContentDocument.CreatedDate]) {
        if (cv.FileExtension == null || !IMAGE_TYPES.contains(cv.FileExtension.toLowerCase())) continue;
        Id recId = docToRecord.get(cv.ContentDocumentId);
        if (!filesByRecord.containsKey(recId)) filesByRecord.put(recId, new List<ContentVersion>());
        filesByRecord.get(recId).add(cv);
    }

    // 3. Replace broken images record by record
    for (SObject rec : broken.values()) {
        String label = objName + ' ' + rec.get('Name') + ' (' + rec.Id + ')';
        List<ContentVersion> files = filesByRecord.get(rec.Id);
        Integer need = brokenCount.get(rec.Id);
        Integer have = (files == null) ? 0 : files.size();
        if (have != need) {
            System.debug('CHECK BY HAND: ' + label + ' has ' + need + ' broken image(s) and ' + have + ' attached image file(s)');
            handCount++;
            continue;
        }
        Boolean tooBig = false;
        for (ContentVersion cv : files) { if (cv.ContentSize > MAX_IMAGE_BYTES) tooBig = true; }
        if (tooBig) {
            System.debug('CHECK BY HAND: ' + label + ' has an image file over 1 MB; re-insert it by hand');
            handCount++;
            continue;
        }

        Integer idx = 0;
        SObject upd = rec.getSObjectType().newSObject(rec.Id);
        for (String f : fields) {
            String html = (String) rec.get(f);
            if (html == null || !BROKEN_IMG.matcher(html).find()) continue;
            String result = '';
            Integer pos = 0;
            Matcher m = BROKEN_IMG.matcher(html);
            while (m.find()) {
                ContentVersion cv = files[idx++];
                System.debug((DRY_RUN ? 'WOULD EMBED: ' : 'EMBED: ') + label + ' field ' + f + ' <- ' + cv.Title + '.' + cv.FileExtension);
                String tag = '[image ' + cv.Title + ']';
                if (!DRY_RUN) {
                    ContentVersion data = [SELECT VersionData FROM ContentVersion WHERE Id = :cv.Id];
                    String mime = cv.FileExtension.toLowerCase() == 'jpg' ? 'jpeg' : cv.FileExtension.toLowerCase();
                    tag = '<img src="data:image/' + mime + ';base64,' + EncodingUtil.base64Encode(data.VersionData)
                        + '" alt="' + cv.Title.escapeHtml4() + '"></img>';
                }
                result += html.substring(pos, m.start()) + tag;
                pos = m.end();
            }
            result += html.substring(pos);
            upd.put(f, result);
        }
        if (!DRY_RUN) update upd;
        fixedCount++;
    }
}
System.debug(fixedCount + ' record(s) ' + (DRY_RUN ? 'to fix' : 'fixed') + ', ' + handCount + ' to check by hand. DRY_RUN = ' + DRY_RUN);
