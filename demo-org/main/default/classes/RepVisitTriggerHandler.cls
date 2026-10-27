/**
 * Personal org only: sample trigger logic for Rep Visits, used to test how GuidePilot explains
 * Apex automation to reps.
 */
public with sharing class RepVisitTriggerHandler {

    @TestVisible private static final Integer DEFAULT_VISIT_MINUTES = 30;

    public static void handle(List<Rep_Visit__c> visits, Map<Id, Rep_Visit__c> oldVisits) {
        for (Rep_Visit__c visit : visits) {
            defaultPlannedEnd(visit);
            if (oldVisits != null) {
                preventReopening(visit, oldVisits.get(visit.Id));
            }
        }
    }

    // A visit saved with a Planned Start but no Planned End is booked for 30 minutes.
    private static void defaultPlannedEnd(Rep_Visit__c visit) {
        if (visit.Planned_Start__c != null && visit.Planned_End__c == null) {
            visit.Planned_End__c = visit.Planned_Start__c.addMinutes(DEFAULT_VISIT_MINUTES);
        }
    }

    // Completed visits are final: they can't go back to Planned or Scheduled.
    private static void preventReopening(Rep_Visit__c visit, Rep_Visit__c old) {
        Boolean wasCompleted = old != null && old.Status__c == 'Completed';
        Boolean reopened = visit.Status__c == 'Planned' || visit.Status__c == 'Scheduled';
        if (wasCompleted && reopened) {
            visit.Status__c.addError('A completed visit can\'t be moved back to Planned or Scheduled. Create a new visit instead.');
        }
    }
}
