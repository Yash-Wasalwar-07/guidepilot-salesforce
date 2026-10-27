/**
 * Personal org only: sample trigger for testing how GuidePilot reads Apex automation.
 * All logic lives in RepVisitTriggerHandler.
 */
trigger RepVisitTrigger on Rep_Visit__c (before insert, before update) {
    RepVisitTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}
