// =====================================================================
// Clone permission set + permission set group assignments AND managed
// package licenses from a TEMPLATE user to a list of TARGET users.
//
// How to run: Setup gear > Developer Console > Debug >
//             Open Execute Anonymous Window > paste > Execute.
//             Then Debug > Open Log (or tick "Open Log") and read
//             the lines that start with "RESULT".
//
// Safe to re-run: it only adds what a target user doesn't have.
// Works in any org: everything is found by username, nothing by Id.
// =====================================================================

// ---- 1. EDIT THESE TWO LINES ----------------------------------------
String templateUsername = 'ginger@basfplay.com';
List<String> targetUsernames = new List<String>{
    'user.one@basfplay.com',
    'user.two@basfplay.com'
};
// ---------------------------------------------------------------------

// Find the template user
List<User> tmpl = [SELECT Id, Name FROM User WHERE Username = :templateUsername LIMIT 1];
if (tmpl.isEmpty()) {
    System.debug('RESULT: template user not found: ' + templateUsername);
    return;
}
Id templateId = tmpl[0].Id;

// Read the template user's direct assignments (groups and standalone sets).
// Sets that come *through* a group are skipped - the group brings them.
Set<Id> tmplGroups = new Set<Id>();
Set<Id> tmplSets   = new Set<Id>();
for (PermissionSetAssignment a : [
        SELECT PermissionSetId, PermissionSetGroupId, PermissionSet.IsOwnedByProfile
        FROM PermissionSetAssignment WHERE AssigneeId = :templateId]) {
    if (a.PermissionSetGroupId != null)            tmplGroups.add(a.PermissionSetGroupId);
    else if (!a.PermissionSet.IsOwnedByProfile)    tmplSets.add(a.PermissionSetId);
}
System.debug('RESULT: template ' + tmpl[0].Name + ' has '
    + tmplGroups.size() + ' groups and ' + tmplSets.size() + ' standalone sets');

// Find the target users
Map<String, User> targets = new Map<String, User>();
for (User u : [SELECT Id, Name, Username FROM User WHERE Username IN :targetUsernames]) {
    targets.put(u.Username.toLowerCase(), u);
}
for (String un : targetUsernames) {
    if (!targets.containsKey(un.toLowerCase())) System.debug('RESULT: target user not found: ' + un);
}

// What the targets already have
Map<Id, Set<Id>> haveGroups = new Map<Id, Set<Id>>();
Map<Id, Set<Id>> haveSets   = new Map<Id, Set<Id>>();
Set<Id> targetIds = new Set<Id>();
for (User u : targets.values()) {
    targetIds.add(u.Id);
    haveGroups.put(u.Id, new Set<Id>());
    haveSets.put(u.Id, new Set<Id>());
}
for (PermissionSetAssignment a : [
        SELECT AssigneeId, PermissionSetId, PermissionSetGroupId
        FROM PermissionSetAssignment WHERE AssigneeId IN :targetIds]) {
    if (a.PermissionSetGroupId != null) haveGroups.get(a.AssigneeId).add(a.PermissionSetGroupId);
    else                                haveSets.get(a.AssigneeId).add(a.PermissionSetId);
}

// Build the missing assignments
List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
for (User u : targets.values()) {
    for (Id g : tmplGroups) {
        if (!haveGroups.get(u.Id).contains(g))
            toInsert.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = g));
    }
    for (Id s : tmplSets) {
        if (!haveSets.get(u.Id).contains(s))
            toInsert.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = s));
    }
}

// Insert, allowing partial success, and report per user
Map<Id, Integer> added  = new Map<Id, Integer>();
Map<Id, List<String>> failed = new Map<Id, List<String>>();
Database.SaveResult[] results = Database.insert(toInsert, false);
for (Integer i = 0; i < results.size(); i++) {
    Id who = toInsert[i].AssigneeId;
    if (results[i].isSuccess()) {
        added.put(who, (added.containsKey(who) ? added.get(who) : 0) + 1);
    } else {
        if (!failed.containsKey(who)) failed.put(who, new List<String>());
        Id what = toInsert[i].PermissionSetGroupId != null
                ? toInsert[i].PermissionSetGroupId : toInsert[i].PermissionSetId;
        failed.get(who).add(what + ': ' + results[i].getErrors()[0].getMessage());
    }
}

// ---- Package licenses (e.g. ComplianceQuest, CQ Extension) --------------
Set<Id> tmplPkgs = new Set<Id>();
for (UserPackageLicense l : [SELECT PackageLicenseId FROM UserPackageLicense WHERE UserId = :templateId]) {
    tmplPkgs.add(l.PackageLicenseId);
}
Map<Id, String> pkgNames = new Map<Id, String>();
for (PackageLicense p : [SELECT Id, NamespacePrefix FROM PackageLicense WHERE Id IN :tmplPkgs]) {
    pkgNames.put(p.Id, p.NamespacePrefix);
}
System.debug('RESULT: template holds package licenses: ' + pkgNames.values());

Map<Id, Set<Id>> havePkgs = new Map<Id, Set<Id>>();
for (Id uid : targetIds) havePkgs.put(uid, new Set<Id>());
for (UserPackageLicense l : [SELECT UserId, PackageLicenseId FROM UserPackageLicense WHERE UserId IN :targetIds]) {
    havePkgs.get(l.UserId).add(l.PackageLicenseId);
}
List<UserPackageLicense> pkgInsert = new List<UserPackageLicense>();
for (User u : targets.values()) {
    for (Id p : tmplPkgs) {
        if (!havePkgs.get(u.Id).contains(p))
            pkgInsert.add(new UserPackageLicense(UserId = u.Id, PackageLicenseId = p));
    }
}
Database.SaveResult[] pkgResults = Database.insert(pkgInsert, false);
Map<Id, Integer> pkgAdded = new Map<Id, Integer>();
for (Integer i = 0; i < pkgResults.size(); i++) {
    Id who = pkgInsert[i].UserId;
    if (pkgResults[i].isSuccess()) {
        pkgAdded.put(who, (pkgAdded.containsKey(who) ? pkgAdded.get(who) : 0) + 1);
    } else {
        if (!failed.containsKey(who)) failed.put(who, new List<String>());
        failed.get(who).add('package ' + pkgNames.get(pkgInsert[i].PackageLicenseId)
            + ': ' + pkgResults[i].getErrors()[0].getMessage());
    }
}

for (User u : targets.values()) {
    Integer n = added.containsKey(u.Id) ? added.get(u.Id) : 0;
    Integer pk = pkgAdded.containsKey(u.Id) ? pkgAdded.get(u.Id) : 0;
    System.debug('RESULT: ' + u.Name + ' (' + u.Username + ') - permissions added ' + n
        + ', package licenses added ' + pk
        + ', failed ' + (failed.containsKey(u.Id) ? failed.get(u.Id).size() : 0));
    if (failed.containsKey(u.Id)) {
        for (String f : failed.get(u.Id)) System.debug('RESULT:    ' + f);
    }
}
