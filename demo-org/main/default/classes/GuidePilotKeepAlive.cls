/**
 * Keeps the GuidePilot API awake on hosting that sleeps when idle (e.g. Render's free plan,
 * which stops after 15 minutes without requests and then answers 503 while waking up).
 * Pings /health through the GuidePilot_API Named Credential every 10 minutes.
 *
 *   GuidePilotKeepAlive.start();   // Execute Anonymous, once: schedules six hourly jobs (:00, :10, ... :50)
 *   GuidePilotKeepAlive.stop();    // removes them, e.g. once the API runs on always-on hosting
 */
public with sharing class GuidePilotKeepAlive implements Schedulable {

    @TestVisible private static final String JOB_PREFIX = 'GuidePilot keep-alive';

    public void execute(SchedulableContext context) {
        ping(); // scheduled Apex can't call out directly
    }

    @future(callout=true)
    public static void ping() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:GuidePilot_API/health');
        req.setMethod('GET');
        req.setTimeout(120000); // long enough for a sleeping instance to wake
        try {
            HttpResponse res = new Http().send(req);
            System.debug(LoggingLevel.INFO, 'GuidePilot keep-alive: HTTP ' + res.getStatusCode());
        } catch (CalloutException e) {
            System.debug(LoggingLevel.WARN, 'GuidePilot keep-alive failed: ' + e.getMessage());
        }
    }

    public static void start() {
        stop();
        for (Integer minute = 0; minute < 60; minute += 10) {
            String label = JOB_PREFIX + ' :' + String.valueOf(minute).leftPad(2, '0');
            System.schedule(label, '0 ' + minute + ' * * * ?', new GuidePilotKeepAlive());
        }
    }

    public static void stop() {
        for (CronTrigger job : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :(JOB_PREFIX + '%')]) {
            System.abortJob(job.Id);
        }
    }
}
