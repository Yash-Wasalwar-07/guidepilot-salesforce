// Personal org only: three published Knowledge articles for testing GuidePilot's article search.
List<Knowledge__kav> articles = new List<Knowledge__kav>{
    new Knowledge__kav(Title = 'Changing the owner of an Account', UrlName = 'gp-changing-account-owner',
        Summary = 'What happens to opportunities, visits and tasks when an Account changes owner.',
        Answer__c = '<p>When you change the Account Owner, open opportunities owned by the previous owner move to the new owner only if you tick <b>Transfer open opportunities</b>. Closed opportunities stay with their original owner.</p><p>Open tasks and upcoming Rep Visits are not moved automatically: the previous owner should reassign them. Ownership changes for accounts in another territory need your district manager\'s approval first.</p>'),
    new Knowledge__kav(Title = 'Rep Visit approvals and Educational visits', UrlName = 'gp-rep-visit-approvals',
        Summary = 'Which Rep Visits need approval, and how to submit them.',
        Answer__c = '<p>Only <b>Educational</b> visits need approval. Submit the visit for approval while it is Planned: your manager approves or rejects it in Salesforce. Detail, Reminder and Brief Interaction visits do not need approval.</p>'),
    new Knowledge__kav(Title = 'Closing an opportunity as lost', UrlName = 'gp-closing-opportunity-lost',
        Summary = 'Steps for closing an opportunity as Closed Lost.',
        Answer__c = '<p>Set the Stage to <b>Closed Lost</b> and set the Close Date to the day the customer declined. Add the reason in Next Step or the description so the loss can be reviewed in the monthly pipeline meeting.</p>')
};
insert articles;
for (Knowledge__kav a : [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id IN :articles]) {
    KbManagement.PublishingService.publishArticle(a.KnowledgeArticleId, true);
}
System.debug('GPRESULT published ' + articles.size());
