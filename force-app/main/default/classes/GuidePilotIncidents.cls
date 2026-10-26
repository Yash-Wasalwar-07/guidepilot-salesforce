/**
 * Raises a GuidePilot Incident (a mock ServiceNow incident) when GuidePilot can't answer a
 * question, owned by the L1 support queue. Stands in for a real ServiceNow incident until that
 * integration is connected.
 *
 * Runs without sharing: reps don't need access to the object to raise an incident, and the queue
 * owns it. The rep gets read access to their own incident so they can follow it.
 */
public without sharing class GuidePilotIncidents {

    // A Custom Label, so an org can point incidents at its own queue without a code change.
    @TestVisible private static String queueName = Label.GuidePilot_Incident_Queue;

    /** Creates (or, for a repeated poll of the same answer, finds) the incident for a routed answer. */
    public static GuidePilot_Incident__c raise(Map<String, Object> result, String turnId) {
        Map<String, Object> page = result.get('page') instanceof Map<String, Object>
            ? (Map<String, Object>) result.get('page')
            : new Map<String, Object>();
        String question = text(result.get('question'));
        Group queue = findQueue();

        GuidePilot_Incident__c incident = new GuidePilot_Incident__c(
            Short_Description__c = (String.isBlank(question) ? 'Unanswered GuidePilot question' : question).abbreviate(160),
            Description__c = describe(result, page).left(32768),
            Caller__c = UserInfo.getUserId(),
            State__c = 'New',
            Priority__c = '4 - Low',
            Category__c = 'Documentation Gap',
            Assignment_Group__c = queue != null ? queue.Name : null,
            Object_Name__c = text(page.get('object_name')).left(80),
            Field_Name__c = text(page.get('field_in_focus')).left(80),
            Record_Id__c = text(page.get('record_id')).left(18),
            Turn_Id__c = turnId
        );
        if (queue != null) {
            incident.OwnerId = queue.Id;
        }
        if (String.isNotBlank(turnId)) {
            upsert incident Turn_Id__c; // the panel may poll a finished answer more than once
        } else {
            insert incident;
        }
        if (queue != null) {
            // Owned by the queue, so share it with the rep who asked.
            Database.insert(new GuidePilot_Incident__Share(
                ParentId = incident.Id, UserOrGroupId = UserInfo.getUserId(), AccessLevel = 'Read', RowCause = 'Manual'
            ), false);
        }
        return [SELECT Id, Name, Assignment_Group__c FROM GuidePilot_Incident__c WHERE Id = :incident.Id];
    }

    public static String link(Id incidentId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/GuidePilot_Incident__c/' + incidentId + '/view';
    }

    private static Group findQueue() {
        List<Group> queues = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND DeveloperName = :queueName LIMIT 1];
        if (queues.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'GuidePilot incident queue not found: ' + queueName);
            return null;
        }
        return queues[0];
    }

    // Everything L1 needs to pick it up: the question, where it was asked, what was searched, what GuidePilot said.
    private static String describe(Map<String, Object> result, Map<String, Object> page) {
        List<String> lines = new List<String>{ 'Question: ' + text(result.get('question')) };
        if (String.isNotBlank(text(result.get('rewritten_question')))) {
            lines.add('Understood as: ' + text(result.get('rewritten_question')));
        }
        if (!page.isEmpty()) {
            lines.add('Page: ' + text(page.get('object_name')) + ' (' + text(page.get('mode')) + ')'
                + (String.isNotBlank(text(page.get('field_in_focus'))) ? ', field ' + text(page.get('field_in_focus')) : '')
                + (String.isNotBlank(text(page.get('record_id'))) ? ', record ' + text(page.get('record_id')) : ''));
        }
        lines.add('Coverage: ' + text(result.get('coverage')));
        if (result.get('scouts') instanceof List<Object>) {
            List<String> searched = new List<String>();
            for (Object o : (List<Object>) result.get('scouts')) {
                if (o instanceof Map<String, Object>) {
                    Map<String, Object> s = (Map<String, Object>) o;
                    searched.add('- ' + text(s.get('scout')) + ': ' + text(s.get('status'))
                        + (String.isNotBlank(text(s.get('note'))) ? ' (' + text(s.get('note')) + ')' : ''));
                }
            }
            if (!searched.isEmpty()) {
                lines.add('Sources searched:\n' + String.join(searched, '\n'));
            }
        }
        lines.add('GuidePilot replied:\n' + text(result.get('answer')));
        return String.join(lines, '\n\n');
    }

    private static String text(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}
