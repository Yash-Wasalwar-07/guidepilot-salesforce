// GuidePilot test data: doctors (Contacts) at the GPTEST accounts, and 80 Rep Visits.
List<Account> accts = [SELECT Id FROM Account WHERE AccountNumber LIKE 'GPTEST-%' ORDER BY AccountNumber];
if (![SELECT Id FROM Rep_Visit__c LIMIT 1].isEmpty()) { System.debug('GP_SKIP visits already exist'); return; }
List<String> firstNames = new List<String>{'Jane','Arjun','Maria','David','Priya','Thomas','Aisha','Robert','Mei','Carlos','Fatima','Lukas','Sarah','Kenji','Elena','Omar','Grace','Daniel','Nina','Samuel'};
List<String> lastNames = new List<String>{'Smith','Rao','Garcia','Chen','Patel','Mueller','Khan','Johnson','Lin','Lopez','Hassan','Weber','Brown','Tanaka','Rossi','Ali','Kim','Okafor','Novak','Reed'};
List<String> specialties = new List<String>{'Cardiologist','Oncologist','Endocrinologist','Pulmonologist','Neurologist','Rheumatologist','Dermatologist','Pediatrician','General Practitioner','Infectious Disease Specialist'};
List<Contact> doctors = new List<Contact>();
for (Integer i = 0; i < 20; i++) {
    doctors.add(new Contact(Salutation = 'Dr.', FirstName = firstNames[i], LastName = lastNames[i],
        Title = specialties[Math.mod(i, specialties.size())], AccountId = accts[Math.mod(i, accts.size())].Id));
}
insert doctors;

List<String> types = new List<String>();
for (Integer i = 0; i < 40; i++) types.add('Detail');
for (Integer i = 0; i < 20; i++) types.add('Reminder');
for (Integer i = 0; i < 12; i++) types.add('Educational');
for (Integer i = 0; i < 8; i++) types.add('Brief Interaction');
Map<String, Integer> minutes = new Map<String, Integer>{'Detail' => 45, 'Reminder' => 15, 'Educational' => 60, 'Brief Interaction' => 4};
Map<String, String> outcomes = new Map<String, String>{
    'Detail' => 'Full product discussion; HCP interested in the outcomes data.',
    'Reminder' => 'Short follow-up on the previous discussion; questions answered.',
    'Educational' => 'Non-promotional scientific exchange on the latest guidelines.',
    'Brief Interaction' => 'Quick hallway conversation, under 5 minutes.'
};
DateTime now = DateTime.now();
List<Rep_Visit__c> visits = new List<Rep_Visit__c>();
for (Integer i = 0; i < 80; i++) {
    String t = types[Math.mod(i * 37, 80)]; // spread the types across statuses
    String status = i < 60 ? 'Completed' : (i < 70 ? 'Scheduled' : (i < 78 ? 'Planned' : 'Cancelled'));
    Boolean past = status == 'Completed' || status == 'Cancelled';
    DateTime startAt = past ? now.addDays(-(5 + Math.mod(i * 11, 300))) : now.addDays(3 + (i - 60) * 3);
    Contact doc = doctors[Math.mod(i * 7, 20)];
    Rep_Visit__c v = new Rep_Visit__c(Account__c = doc.AccountId, Contact__c = doc.Id, Visit_Type__c = t, Status__c = status,
        Planned_Start__c = startAt, Planned_End__c = startAt.addMinutes(minutes.get(t)));
    if (status == 'Completed') {
        v.Outcome__c = outcomes.get(t);
        v.Next_Steps__c = 'Send follow-up material and confirm the next visit.';
        v.Follow_Up_Date__c = startAt.date().addDays(14);
    }
    visits.add(v);
}
insert visits;
System.debug('GP_DATA doctors=' + doctors.size() + ' visits=' + visits.size());
