/**
 * Server side of the GuidePilot chat panel.
 *
 * The browser never talks to the agent API directly. This class calls it through the
 * GuidePilot_API Named Credential, so the API key stays in Salesforce, and it adds the
 * rep's identity from the Salesforce session (UserInfo), which the browser can't fake.
 */
public with sharing class GuidePilotController {

    private static final String ENDPOINT = 'callout:GuidePilot_API';
    private static final String ASSISTANT = 'guidepilot';
    private static final Integer TIMEOUT_MS = 120000; // Salesforce's maximum; covers a sleeping host waking up
    @TestVisible private static final String STARTING_UP = 'GuidePilot is starting up. Please try again in a few seconds.';
    private static final Integer MAX_QUESTION_CHARS = 4000;
    private static final Pattern SESSION_ID = Pattern.compile('[0-9a-f]{32}');
    private static final Pattern API_NAME = Pattern.compile('[A-Za-z][A-Za-z0-9_]{0,79}');
    private static final Set<String> MODES = new Set<String>{ 'new', 'edit', 'view' };

    /** Starts a chat for the current user on the given page. Returns { session_id, ... }. */
    @AuraEnabled
    public static Map<String, Object> startSession(String objectApiName, String recordId, String mode, String fieldInFocus) {
        Map<String, Object> body = new Map<String, Object>{
            'assistant' => ASSISTANT,
            'user' => UserInfo.getUserId(),
            'page' => page(objectApiName, recordId, mode, fieldInFocus)
        };
        return send('POST', '/api/sessions', body);
    }

    /**
     * Asks a question. The page is sent every time, since the rep may have navigated or moved
     * to another field (fieldInFocus comes from entry forms via the GuidePilotContext channel).
     */
    @AuraEnabled
    public static Map<String, Object> ask(
        String sessionId, String question, String objectApiName, String recordId, String mode, String fieldInFocus
    ) {
        checkSession(sessionId);
        if (String.isBlank(question) || question.length() > MAX_QUESTION_CHARS) {
            throw error('Please ask a question of up to ' + MAX_QUESTION_CHARS + ' characters.');
        }
        Map<String, Object> body = new Map<String, Object>{
            'question' => question.trim(),
            'page' => page(objectApiName, recordId, mode, fieldInFocus)
        };
        return withIncident(send('POST', '/api/sessions/' + sessionId + '/messages', body), null);
    }

    /**
     * Starts answering in the background and returns { turn_id }. Apex can't stream, so the panel
     * calls pollTurn about once a second and shows the answer as it's being written.
     */
    @AuraEnabled
    public static Map<String, Object> startTurn(
        String sessionId, String question, String objectApiName, String recordId, String mode, String fieldInFocus
    ) {
        checkSession(sessionId);
        if (String.isBlank(question) || question.length() > MAX_QUESTION_CHARS) {
            throw error('Please ask a question of up to ' + MAX_QUESTION_CHARS + ' characters.');
        }
        Map<String, Object> body = new Map<String, Object>{
            'question' => question.trim(),
            'page' => page(objectApiName, recordId, mode, fieldInFocus)
        };
        return send('POST', '/api/sessions/' + sessionId + '/turns', body);
    }

    /** Progress of a background answer: { status, stage, answer_so_far, result, error }. */
    @AuraEnabled
    public static Map<String, Object> pollTurn(String sessionId, String turnId) {
        checkSession(sessionId);
        if (turnId == null || !SESSION_ID.matcher(turnId).matches()) {
            throw error('That answer is no longer available. Please ask again.');
        }
        Map<String, Object> progress = send('GET', '/api/sessions/' + sessionId + '/turns/' + turnId, null);
        if (progress.get('status') == 'done' && progress.get('result') instanceof Map<String, Object>) {
            withIncident((Map<String, Object>) progress.get('result'), turnId);
        }
        return progress;
    }

    /** Records thumbs up or down on the latest answer. */
    @AuraEnabled
    public static void feedback(String sessionId, String rating, String comment) {
        checkSession(sessionId);
        if (rating != 'up' && rating != 'down') {
            throw error('Rating must be up or down.');
        }
        Map<String, Object> body = new Map<String, Object>{ 'rating' => rating };
        if (String.isNotBlank(comment)) {
            body.put('comment', comment.left(1000));
        }
        send('POST', '/api/sessions/' + sessionId + '/feedback', body);
    }

    // -- helpers ---------------------------------------------------------------------

    /**
     * When GuidePilot couldn't answer, raise an incident for L1 support and tell the rep its number.
     * A failure here never hides the answer: it's logged and the answer is returned as it was.
     */
    private static Map<String, Object> withIncident(Map<String, Object> result, String turnId) {
        if (result == null || result.get('routed_to_sales_ops') != true) {
            return result;
        }
        try {
            GuidePilot_Incident__c incident = GuidePilotIncidents.raise(result, turnId);
            result.put('incident', new Map<String, Object>{ 'id' => incident.Id, 'number' => incident.Name });
            String team = String.isNotBlank(incident.Assignment_Group__c) ? incident.Assignment_Group__c : 'support';
            result.put('answer', String.valueOf(result.get('answer'))
                + '\n\nIncident ' + incident.Name + ' has been raised for ' + team + '. Track it here: '
                + GuidePilotIncidents.link(incident.Id));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GuidePilot incident could not be raised: ' + e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> page(String objectApiName, String recordId, String mode, String fieldInFocus) {
        if (String.isBlank(objectApiName)) {
            return null; // not on a record page (e.g. Home): the agent works without page context
        }
        if (!API_NAME.matcher(objectApiName).matches()) {
            throw error('Unsupported page.');
        }
        Map<String, Object> page = new Map<String, Object>{
            'object_name' => objectApiName,
            'mode' => MODES.contains(mode) ? mode : 'view'
        };
        if (String.isNotBlank(fieldInFocus)) {
            if (!API_NAME.matcher(fieldInFocus).matches()) {
                throw error('Unsupported page.');
            }
            page.put('field_in_focus', fieldInFocus);
        }
        if (String.isNotBlank(recordId)) {
            try {
                page.put('record_id', String.valueOf(Id.valueOf(recordId)));
            } catch (StringException e) {
                throw error('Unsupported page.');
            }
        }
        return page;
    }

    private static void checkSession(String sessionId) {
        if (sessionId == null || !SESSION_ID.matcher(sessionId).matches()) {
            throw error('Your GuidePilot session has expired. Please ask again.');
        }
    }

    private static Map<String, Object> send(String method, String path, Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT + path);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        if (body != null) {
            req.setBody(JSON.serialize(body, true));
        }

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            System.debug(LoggingLevel.ERROR, 'GuidePilot callout failed: ' + e.getMessage());
            throw error('GuidePilot is not reachable right now. Please try again shortly.');
        }

        Integer status = res.getStatusCode();
        String text = res.getBody();
        Map<String, Object> data = String.isBlank(text) ? new Map<String, Object>() : parse(text);
        if (status >= 300) {
            System.debug(LoggingLevel.ERROR, 'GuidePilot API ' + status + ': ' + text);
            if (status == 404) {
                throw error('Your GuidePilot session has expired. Please ask again.');
            }
            Object message = data.containsKey('error') ? data.get('error') : null;
            if (message != null) {
                throw error(String.valueOf(message));
            }
            // No GuidePilot error body: the hosting platform answered, usually while the service wakes up.
            if (status == 502 || status == 503 || status == 504) {
                throw error(STARTING_UP);
            }
            throw error('GuidePilot could not answer (error ' + status + ').');
        }
        return data;
    }

    private static Map<String, Object> parse(String text) {
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(text);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message); // makes the message visible in Apex tests too
        return e;
    }
}
