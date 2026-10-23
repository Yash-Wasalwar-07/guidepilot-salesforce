import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import GUIDEPILOT_CONTEXT from '@salesforce/messageChannel/GuidePilotContext__c';
import startSession from '@salesforce/apex/GuidePilotController.startSession';
import ask from '@salesforce/apex/GuidePilotController.ask';
import sendFeedback from '@salesforce/apex/GuidePilotController.feedback';

const WAKE_RETRIES = 3;
const WAKE_WAIT_MS = 10000;

const COVERAGE = {
    full: { label: 'Answered', css: 'badge badge_full' },
    partial: { label: 'Partly documented', css: 'badge badge_partial' },
    none: { label: 'Not documented', css: 'badge badge_none' }
};

/**
 * GuidePilot chat panel. Works in the utility bar (follows whatever page the rep is on)
 * or on a record page. Reads the object, record and new/edit/view mode automatically;
 * the rep's identity is added server side by GuidePilotController.
 *
 * Standard record pages don't reveal which field has focus, so entry forms can publish it
 * on the GuidePilotContext message channel; the panel sends it with the next question.
 */
export default class GuidePilot extends LightningElement {
    @api recordId; // set by the platform on record pages
    @api objectApiName; // set by the platform on record pages
    @api title = 'GuidePilot';

    pageRef;
    sessionId;
    messages = [];
    question = '';
    busy = false;
    busyText = '';
    scrollPending = false;
    nextId = 0;
    focus = null; // { objectApiName, recordId, mode, fieldApiName } from an entry form
    subscription = null;

    @wire(MessageContext)
    messageContext;

    // Labels for display only ("Rep Visit", "Visit Type"); the API names are what gets sent.
    @wire(getObjectInfo, { objectApiName: '$currentObject' })
    objectInfo;

    get currentObject() {
        return this.page.objectApiName || undefined;
    }

    @wire(CurrentPageReference)
    setPageRef(ref) {
        this.pageRef = ref;
    }

    connectedCallback() {
        // Application scope: the panel may sit in the utility bar, outside the page's own area.
        this.subscription = subscribe(this.messageContext, GUIDEPILOT_CONTEXT, (message) => this.setFocus(message), {
            scope: APPLICATION_SCOPE
        });
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    setFocus(message) {
        if (!message || !message.objectApiName || !message.fieldApiName) {
            return;
        }
        this.focus = {
            objectApiName: message.objectApiName,
            recordId: message.recordId || null,
            mode: ['new', 'edit', 'view'].includes(message.mode) ? message.mode : null,
            fieldApiName: message.fieldApiName
        };
    }

    get page() {
        const attrs = (this.pageRef && this.pageRef.attributes) || {};
        const action = attrs.actionName;
        let mode = action === 'new' ? 'new' : action === 'edit' ? 'edit' : 'view';
        let objectApiName = attrs.objectApiName || this.objectApiName || null;
        let recordId = mode === 'new' ? null : attrs.recordId || this.recordId || null;
        let fieldInFocus = null;
        // Use the form's field only while the rep is still on the record it came from.
        const f = this.focus;
        const samePage =
            f && (!objectApiName || f.objectApiName === objectApiName) && (!recordId || !f.recordId || f.recordId === recordId);
        if (samePage) {
            objectApiName = f.objectApiName;
            recordId = f.recordId || recordId;
            mode = f.mode || mode;
            fieldInFocus = f.fieldApiName;
        }
        return { objectApiName, recordId, mode, fieldInFocus };
    }

    get pageLabel() {
        const p = this.page;
        if (!p.objectApiName) {
            return 'Open a record to ask about its fields.';
        }
        const info = this.objectInfo && this.objectInfo.data;
        const objectLabel = (info && info.label) || p.objectApiName;
        const field = p.fieldInFocus && info && info.fields[p.fieldInFocus];
        const fieldLabel = field ? field.label : p.fieldInFocus;
        const verb = { new: 'Creating a new', edit: 'Editing a', view: 'Viewing a' }[p.mode];
        return `${verb} ${objectLabel}` + (fieldLabel ? ` · field: ${fieldLabel}` : '');
    }

    // An example built from this object's own fields, so the hint fits any org and any object.
    get exampleQuestion() {
        const info = this.objectInfo && this.objectInfo.data;
        const fields = info ? Object.values(info.fields) : [];
        const pick =
            fields.find((f) => f.custom && f.dataType === 'Picklist') ||
            fields.find((f) => f.dataType === 'Picklist' && f.updateable) ||
            fields.find((f) => f.custom && f.updateable);
        return `"What does ${pick ? pick.label : 'the Status field'} mean?"`;
    }

    get isEmpty() {
        return this.messages.length === 0;
    }

    get cannotSend() {
        return this.busy || !this.question.trim();
    }

    handleInput(event) {
        this.question = event.target.value || '';
    }

    handleKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.send();
        }
    }

    async send() {
        const question = this.question.trim();
        if (!question || this.busy) {
            return;
        }
        this.busy = true;
        this.busyText = 'Searching training, documentation and data...';
        this.question = '';
        this.push({ role: 'rep', text: question });
        try {
            const result = await this.askWhileWaking(question);
            this.push({ role: 'agent', text: result.answer, coverage: result.coverage });
        } catch (error) {
            this.push({ role: 'error', text: errorMessage(error) });
        } finally {
            this.busy = false;
        }
    }

    // A host that sleeps when idle answers "starting up" for a while: wait and retry instead of failing.
    async askWhileWaking(question) {
        for (let attempt = 0; ; attempt++) {
            try {
                return await this.askWithSession(question);
            } catch (error) {
                if (attempt >= WAKE_RETRIES || !errorMessage(error).includes('starting up')) {
                    throw error;
                }
                this.busyText = 'GuidePilot is waking up, this can take a minute...';
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                await new Promise((resolve) => setTimeout(resolve, WAKE_WAIT_MS));
            }
        }
    }

    async askWithSession(question) {
        const page = this.page;
        if (!this.sessionId) {
            this.sessionId = (await startSession(page)).session_id;
        }
        try {
            return await ask({ sessionId: this.sessionId, question, ...page });
        } catch (error) {
            if (!errorMessage(error).includes('expired')) {
                throw error;
            }
            // Sessions expire after inactivity on the server: start a new one and retry once.
            this.sessionId = (await startSession(page)).session_id;
            return ask({ sessionId: this.sessionId, question, ...page });
        }
    }

    async rate(event) {
        const id = Number(event.currentTarget.dataset.id);
        const rating = event.currentTarget.dataset.rating;
        this.update(id, { canRate: false, rated: 'Sending feedback...' });
        try {
            await sendFeedback({ sessionId: this.sessionId, rating, comment: null });
            this.update(id, { rated: 'Thanks for the feedback.' });
        } catch (error) {
            this.update(id, { rated: 'Feedback could not be sent.' });
        }
    }

    push({ role, text, coverage }) {
        const badge = coverage ? COVERAGE[coverage] : null;
        // Feedback rates the latest answer only, so older answers lose their buttons.
        const older = role === 'agent' ? this.messages.map((m) => ({ ...m, canRate: false })) : this.messages;
        this.messages = [
            ...older,
            {
                id: this.nextId++,
                role,
                text,
                css: `message message_${role}`,
                badgeLabel: badge ? badge.label : null,
                badgeCss: badge ? badge.css : null,
                canRate: role === 'agent',
                rated: null
            }
        ];
        this.scrollPending = true;
    }

    update(id, changes) {
        this.messages = this.messages.map((m) => (m.id === id ? { ...m, ...changes } : m));
    }

    renderedCallback() {
        if (this.scrollPending && this.refs.log) {
            this.refs.log.scrollTop = this.refs.log.scrollHeight;
            this.scrollPending = false;
        }
    }
}

function errorMessage(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong.';
}
