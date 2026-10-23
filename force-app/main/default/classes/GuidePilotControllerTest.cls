@IsTest
private class GuidePilotControllerTest {

    private static final String SESSION = '0123456789abcdef0123456789abcdef';

    /** Fakes the agent API and remembers the last request. */
    private class ApiMock implements HttpCalloutMock {
        Integer status;
        String body;
        HttpRequest last;

        ApiMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            last = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            if (body != null) {
                res.setBody(body);
            }
            return res;
        }
    }

    @IsTest
    static void startSessionSendsUserAndPage() {
        ApiMock mock = new ApiMock(201, '{"session_id":"' + SESSION + '","assistant":"guidepilot"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = GuidePilotController.startSession('Opportunity', null, 'new', null);
        Test.stopTest();

        Assert.areEqual(SESSION, result.get('session_id'));
        Assert.areEqual('callout:GuidePilot_API/api/sessions', mock.last.getEndpoint());
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.last.getBody());
        Assert.areEqual(UserInfo.getUserId(), sent.get('user'), 'identity must come from the session');
        Assert.areEqual('guidepilot', sent.get('assistant'));
        Map<String, Object> page = (Map<String, Object>) sent.get('page');
        Assert.areEqual('Opportunity', page.get('object_name'));
        Assert.areEqual('new', page.get('mode'));
    }

    @IsTest
    static void askReturnsTheAnswer() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200, '{"answer":"Use Detail [S1].","coverage":"full"}'));

        Test.startTest();
        Map<String, Object> result = GuidePilotController.ask(SESSION, 'What should I pick?', 'Account', null, 'edit', null);
        Test.stopTest();

        Assert.areEqual('Use Detail [S1].', result.get('answer'));
    }

    @IsTest
    static void apiErrorsBecomeReadableMessages() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(429, '{"error":"The AI service is rate limited right now."}'));
        try {
            GuidePilotController.ask(SESSION, 'Hi', null, null, null, null);
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('rate limited'), e.getMessage());
        }
    }

    @IsTest
    static void expiredSessionAsksToRetry() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(404, '{"detail":"Session not found"}'));
        try {
            GuidePilotController.ask(SESSION, 'Hi', null, null, null, null);
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('expired'), e.getMessage());
        }
    }

    @IsTest
    static void rejectsBadInputBeforeCallingOut() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200, '{}'));
        for (String bad : new List<String>{ null, '../admin', 'ABC' }) {
            try {
                GuidePilotController.ask(bad, 'Hi', null, null, null, null);
                Assert.fail('expected an error for ' + bad);
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('expired'));
            }
        }
        try {
            GuidePilotController.startSession('Bad Object!', null, 'new', null);
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Unsupported page'));
        }
    }

    @IsTest
    static void fieldInFocusIsSentAndValidated() {
        ApiMock mock = new ApiMock(200, '{"answer":"Pick Prospecting [S1]."}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GuidePilotController.ask(SESSION, 'What should I pick here?', 'Opportunity', null, 'new', 'StageName');
        Test.stopTest();

        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.last.getBody());
        Map<String, Object> page = (Map<String, Object>) sent.get('page');
        Assert.areEqual('StageName', page.get('field_in_focus'));
        try {
            GuidePilotController.ask(SESSION, 'Hi', 'Opportunity', null, 'new', 'Stage Name!');
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Unsupported page'));
        }
    }

    @IsTest
    static void sleepingHostAsksToRetry() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(503, '<html>Service Unavailable</html>'));
        try {
            GuidePilotController.ask(SESSION, 'Hi', null, null, null, null);
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.areEqual(GuidePilotController.STARTING_UP, e.getMessage());
        }
    }

    @IsTest
    static void startTurnPostsQuestionAndPage() {
        ApiMock mock = new ApiMock(202, '{"turn_id":"' + SESSION + '"}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Map<String, Object> r = GuidePilotController.startTurn(SESSION, 'What should I pick?', 'Opportunity', null, 'new', 'StageName');
        Test.stopTest();
        Assert.areEqual(SESSION, r.get('turn_id'));
        Assert.isTrue(mock.last.getEndpoint().endsWith('/api/sessions/' + SESSION + '/turns'));
        Map<String, Object> page = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.last.getBody())).get('page');
        Assert.areEqual('StageName', page.get('field_in_focus'));
    }

    @IsTest
    static void pollTurnReturnsProgress() {
        ApiMock mock = new ApiMock(200, '{"status":"running","stage":"writing","answer_so_far":"Pick Pros"}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Map<String, Object> r = GuidePilotController.pollTurn(SESSION, SESSION);
        Test.stopTest();
        Assert.areEqual('running', r.get('status'));
        Assert.areEqual('Pick Pros', r.get('answer_so_far'));
        Assert.areEqual('GET', mock.last.getMethod());
        try {
            GuidePilotController.pollTurn(SESSION, '../bad');
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('no longer available'));
        }
    }

    @IsTest
    static void feedbackIsSent() {
        ApiMock mock = new ApiMock(204, null);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GuidePilotController.feedback(SESSION, 'down', 'Wrong field');
        Test.stopTest();

        Assert.isTrue(mock.last.getEndpoint().endsWith('/api/sessions/' + SESSION + '/feedback'));
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.last.getBody());
        Assert.areEqual('down', sent.get('rating'));
        Assert.areEqual('Wrong field', sent.get('comment'));
    }

    @IsTest
    static void unreachableApiHasAFriendlyMessage() {
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());
        try {
            GuidePilotController.startSession(null, null, null, null);
            Assert.fail('expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not reachable'), e.getMessage());
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }
}
