# GuidePilot for Salesforce

The chat panel reps use inside Salesforce. It reads the page the rep is on (object, record, new/edit/view) and asks the GuidePilot agent API through Apex.

```
Lightning component (guidePilot)  →  Apex (GuidePilotController)  →  Named Credential  →  Agent API  →  GuidePilot
 page context, chat UI                 adds UserInfo.getUserId()       holds the API key     /api/sessions, /messages, /feedback
```

| File | Purpose |
| --- | --- |
| `lwc/guidePilot` | Chat panel. Utility bar (follows the current page) or record page. Thumbs up/down on the latest answer. |
| `classes/GuidePilotController` | Calls the API. Sends the rep's identity from the session, never from the browser. Validates input. |
| `classes/GuidePilotControllerTest` | Mocked callout tests (needed to deploy to production). |
| `externalCredentials/GuidePilot_API`, `namedCredentials/GuidePilot_API` | Where the API lives and the `X-API-Key` header. The key itself is set in Setup, never in code. |
| `permissionsets/GuidePilot_User` | Lets a rep use the panel and the credential. |

## Deploying to another org (no customisation needed)

The project has two folders:

| Folder | What | Deploy where |
| --- | --- | --- |
| `force-app/` | **GuidePilot core**: `guidePilot` panel, `GuidePilotController` (+ tests), `GuidePilot_API` Named + External Credential, `GuidePilotContext` message channel, `GuidePilot_User` permission set | **Any org** |
| `demo-org/` | Personal dev org only: our `Rep_Visit__c` (object, layout, list views, tab), Rep Visit permission sets, `guidePilotDemoForm`, `GuidePilotKeepAlive` (free-hosting workaround) | **Never to a client org** (it would clash with the client's own objects) |

Both folders are package directories in `sfdx-project.json`, so each deploys on its own:

```bash
scripts/deploy-guidepilot-core.sh <alias>    # any org: force-app only, via manifest/guidepilot-core.xml
scripts/deploy-demo-org.sh sfdevorg          # personal org only: stops keep-alive, deploys demo-org, restarts it
```

Don't run a bare `sf project deploy start`, or right-click "Deploy" on the project root in VS Code, against a client org: both include `demo-org`. Deploying the `force-app` folder from VS Code is safe.

The core creates no objects, fields, layouts or scheduled jobs, and needs no forms. GuidePilot reads whatever object and fields the org has, and when a rep asks about "this field" without naming it, it asks which field they mean. Entry forms that publish the focused field on `GuidePilotContext` are an optional extra.

Per-org setup (settings and access, not code changes):

1. **API connection:** the agent API reads one org through a read-only integration user. Point it at the org with its `.env` (`SF_DOMAIN`, `SF_CONSUMER_KEY`, `SF_CONSUMER_SECRET`) and give that user read access to the objects and training files reps ask about.
2. **API key:** Setup → Named Credentials → External Credentials → GuidePilot API → Principals → `ApiKey` (secrets can't be deployed). Change the Named Credential URL only if the API is hosted elsewhere.
3. **Access and placement:** assign the **GuidePilot User** permission set; add the **GuidePilot** component to the utility bar or record pages.

## 1. Make the API reachable from Salesforce

Salesforce calls the API from its own servers, so `localhost` won't work.

- **Production:** host the Docker image (`docker run -p 8000:8000 --env-file .env agent-platform`) behind HTTPS on your company's cloud.
- **Trying it from a laptop:** a tunnel gives your local API a temporary public HTTPS address, e.g. `cloudflared tunnel --url http://localhost:8000` or `ngrok http 8000`. Use it only for testing, and with an API key set.

In the API's `.env`:

```
API_KEY=<a long random secret>          # e.g. python3 -c "import secrets; print(secrets.token_urlsafe(32))"
API_ASSISTANTS=guidepilot               # reps can only reach GuidePilot
API_TEST_UI=false                       # no test page or /docs when exposed
```

## 2. Deploy

Install the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli), then from this project folder:

```bash
sf org login web --alias guidepilot-dev            # log in to the target org in the browser
# edit namedCredentials/GuidePilot_API...xml: set the Url to your API's HTTPS address
sf project deploy start --target-org guidepilot-dev --test-level RunSpecifiedTests --tests GuidePilotControllerTest
```

## 3. Configure in Setup

1. **API key:** Setup → Named Credentials → External Credentials → **GuidePilot API** → Principals → **GuidePilotPrincipal** → Authentication Parameters → add `ApiKey` = the same value as `API_KEY`.
2. **Access:** assign the **GuidePilot User** permission set to the reps who should see the panel.
3. **Place the panel:**
   - **Utility bar** (recommended, follows the rep across pages): Setup → App Manager → your app → Edit → Utility Items → Add → **GuidePilot**.
   - **Or on a record page:** open a record → Edit Page → drag **GuidePilot** onto the layout → Save → Activate.

## 4. Check it

Open a record, or click **New** on an object, open the GuidePilot panel, and ask "What does Stage mean?". The answer shows its sources, a coverage badge, and thumbs up/down. Every turn appears in the API's interaction log with the rep's user and the page.

## Notes

- **Field in focus:** standard record pages don't tell components which field the rep clicked, so reps name the field in their question. A custom entry form for an object can pass the focused field later.
- **New-record page context:** on Lightning's standard New dialog the panel knows the object and that it's a new record. In the utility bar it updates as the rep navigates.
- **Timeouts:** Apex waits up to 60 seconds; answers normally take about 10.
- **Troubleshooting:** "GuidePilot is not reachable" means the Named Credential Url is wrong, the API is down, or the tunnel stopped. A 401 in the API log means the `ApiKey` doesn't match `API_KEY`. If reps get a credential access error, check they have the GuidePilot User permission set.

## Test data

`data/guidepilot-test-accounts-opportunities.json` holds 15 healthcare accounts (AccountNumber `GPTEST-001`...`015`) and 60 opportunities across all stages, 4 of them open with past close dates.

```bash
sf data import tree --files data/guidepilot-test-accounts-opportunities.json --target-org sfdevorg   # load
sf apex run --file scripts/apex/delete-guidepilot-test-data.apex --target-org sfdevorg            # remove
```

### Training documents

`data/training-docs/` holds six Word documents uploaded to Salesforce Files for TrainingScout: the Opportunity Stage Guide, Close Date and Forecasting Policy, Amount/Type/Lead Source Guide, Sample and Promotional Compliance Guide (approved material for compliance questions), Field Ops Quick Reference (2024, deliberately conflicts with the Stage Guide on the starting stage), and an account plan for Riverside General Hospital. Each guide is linked to all `GPTEST-` accounts, the account plan to Riverside only; record links are what let the integration user see a file. New files take about a minute to become searchable.

`scripts/apex/delete-guidepilot-test-data.apex` removes these files as well as the test accounts and opportunities.

## Field in focus (entry forms)

Standard record pages don't tell other components which field the rep clicked into. Entry forms can, through the `GuidePilotContext` Lightning message channel:

```js
import { publish, MessageContext } from 'lightning/messageService';
import GUIDEPILOT_CONTEXT from '@salesforce/messageChannel/GuidePilotContext__c';
// on focus of a field (e.g. a wrapper with onfocusin):
publish(this.messageContext, GUIDEPILOT_CONTEXT, {
    objectApiName: 'Rep_Visit__c', recordId: this.recordId || null, mode: 'new', fieldApiName: 'Visit_Type__c'
});
```

The GuidePilot panel listens (application scope, so it works from the utility bar), shows "field: Visit_Type__c" under its title, and sends the field with the next question while the rep stays on that record. `GuidePilotController` validates it and passes it to the API as `field_in_focus`. Pages without such a form keep working; reps name the field instead.

`lwc/guidePilotDemoForm` is a working example: add **GuidePilot Demo Form** to a record page (edits the record) or an app page (creates a new record of its configured object), choose the fields in its properties, click into a field and ask GuidePilot "What should I pick here?".

## Rep Visits (Rep_Visit__c)

Modelled on the Rep Visit integration specification: Account, Contact (the HCP), Visit Type (Detail, Reminder, Educational, Brief Interaction; required, with help text), Status (Planned, Scheduled, Completed, Cancelled), Planned Start/End, Outcome, Next Steps, Follow-Up Date, and a Rep Visits tab.

- Permission sets: **Rep Visit User** (create and edit, tab visible) for reps; **Rep Visit Read Only** for the GuidePilot integration user. Visit Type is required, so it's always visible and isn't listed in them.
- Test data: `scripts/apex/create-guidepilot-visit-data.apex` adds 20 doctors and 80 visits (40 Detail, 20 Reminder, 12 Educational, 8 Brief Interaction; 60 completed, 18 upcoming, 2 cancelled) at the GPTEST accounts. `data/training-docs/Rep Visit Guide.docx` is the matching training guide.
- Try the deck's example: add **GuidePilot Demo Form** to a Rep Visit record page with fields `Account__c,Contact__c,Visit_Type__c,Status__c,Planned_Start__c,Planned_End__c,Outcome__c,Next_Steps__c,Follow_Up_Date__c` (or to an app page with Object `Rep_Visit__c` to create new visits), click into Visit Type and ask GuidePilot "What should I pick here?".

## Keeping a free host awake

Render's free plan stops the API after 15 minutes without requests and answers **503** while it wakes up. Two things handle that:

- **`GuidePilotKeepAlive`** (scheduled Apex) pings `/health` through the Named Credential every 10 minutes. Start: `sf apex run --file scripts/apex/start-guidepilot-keep-alive.apex`; stop (e.g. on always-on hosting): `scripts/apex/stop-guidepilot-keep-alive.apex`. Jobs are named "GuidePilot keep-alive :00" ... ":50" (Setup > Scheduled Jobs).
- If it's asleep anyway, `GuidePilotController` reports "GuidePilot is starting up" for a 502/503/504 without a GuidePilot error body, and the panel shows "GuidePilot is waking up..." and retries up to 3 times, 10 seconds apart. Callouts wait up to 120 seconds, Salesforce's maximum.
