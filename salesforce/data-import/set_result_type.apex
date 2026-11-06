// Run AFTER the SFDMU run. Sets the 4 Regulatory Impact questions to the "Yes/No/NA" Result Type in basfplay.
Id rt = [SELECT Id FROM compliancequest__SQX_Result_Type__c WHERE Name = 'Yes/No/NA' LIMIT 1].Id;
List<compliancequest__SQX_Task_Question__c> qs = [
    SELECT Id FROM compliancequest__SQX_Task_Question__c
    WHERE compliancequest__SQX_Task__r.Name = 'Regulatory Impact'
    AND Name IN ('1','2','3','4')
];
for (compliancequest__SQX_Task_Question__c q : qs) {
    q.compliancequest__SQX_Result_Type__c = rt;
}
update qs;
System.debug('Updated ' + qs.size() + ' questions (expected 4)');
