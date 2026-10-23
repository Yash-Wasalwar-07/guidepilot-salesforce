@IsTest
private class GuidePilotKeepAliveTest {

    private class HealthMock implements HttpCalloutMock {
        HttpRequest last;
        public HttpResponse respond(HttpRequest req) {
            last = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ok"}');
            return res;
        }
    }

    @IsTest
    static void startSchedulesSixJobsAndStopRemovesThem() {
        Test.startTest();
        GuidePilotKeepAlive.start();
        Assert.areEqual(6, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'GuidePilot keep-alive%']);
        GuidePilotKeepAlive.stop();
        Assert.areEqual(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'GuidePilot keep-alive%']);
        Test.stopTest();
    }

    @IsTest
    static void pingCallsHealth() {
        HealthMock mock = new HealthMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new GuidePilotKeepAlive().execute(null);
        Test.stopTest(); // runs the @future ping
        Assert.areEqual('callout:GuidePilot_API/health', mock.last.getEndpoint());
    }
}
