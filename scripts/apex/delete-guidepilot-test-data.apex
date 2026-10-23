// Deletes the GuidePilot test data: Rep Visits, training files, then the test accounts
// (AccountNumber GPTEST-...), which also deletes their opportunities and contacts.
// Run: sf apex run --file scripts/apex/delete-guidepilot-test-data.apex --target-org sfdevorg
List<Rep_Visit__c> visits = [SELECT Id FROM Rep_Visit__c WHERE Account__r.AccountNumber LIKE 'GPTEST-%'];
delete visits;
Set<String> titles = new Set<String>{
    'Opportunity Stage Guide', 'Close Date and Forecasting Policy', 'Opportunity Amount, Type and Lead Source Guide',
    'Field Ops Quick Reference (2024)', 'Sample and Promotional Compliance Guide', 'Account Plan - Riverside General Hospital',
    'Rep Visit Guide'
};
List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Title IN :titles];
delete docs;
List<Account> testAccounts = [SELECT Id FROM Account WHERE AccountNumber LIKE 'GPTEST-%'];
delete testAccounts;
System.debug('Deleted ' + visits.size() + ' visits, ' + docs.size() + ' training files and ' + testAccounts.size()
    + ' test accounts with their opportunities and contacts.');
