@IsTest
private class RepVisitTriggerHandlerTest {

    @IsTest
    static void defaultsPlannedEndAndBlocksReopening() {
        Datetime start = Datetime.now().addDays(1);
        Rep_Visit__c visit = new Rep_Visit__c(Visit_Type__c = 'Detail', Status__c = 'Planned', Planned_Start__c = start);
        insert visit;
        visit = [SELECT Planned_End__c FROM Rep_Visit__c WHERE Id = :visit.Id];
        Assert.areEqual(start.addMinutes(RepVisitTriggerHandler.DEFAULT_VISIT_MINUTES), visit.Planned_End__c);

        visit.Status__c = 'Completed';
        visit.Outcome__c = 'Discussed the new indication.';
        update visit;

        visit.Status__c = 'Scheduled';
        Database.SaveResult result = Database.update(visit, false);
        Assert.isFalse(result.isSuccess(), 'a completed visit must not be reopened');
    }
}
