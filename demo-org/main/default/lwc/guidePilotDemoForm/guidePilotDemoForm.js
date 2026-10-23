import { LightningElement, api, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import GUIDEPILOT_CONTEXT from '@salesforce/messageChannel/GuidePilotContext__c';

const API_NAME = /^[A-Za-z][A-Za-z0-9_]{0,79}$/;

/**
 * Demo entry form that tells GuidePilot which field the rep is in. It shows the pattern a
 * production form (e.g. Call Report or Rep Visit) needs: publish the field on focus to the
 * GuidePilotContext channel. On a record page it edits that record; on an app page it
 * creates a new record of the configured object.
 */
export default class GuidePilotDemoForm extends LightningElement {
    @api recordId; // set by the platform on record pages
    @api objectApiName; // set by the platform on record pages
    @api formObject = 'Opportunity'; // used on app pages, where there is no record
    @api fieldList = 'Name,StageName,CloseDate,Amount,Type,LeadSource';
    @api title = 'Details';

    lastField;

    @wire(MessageContext)
    messageContext;

    get object() {
        return this.objectApiName || this.formObject;
    }

    get fields() {
        return (this.fieldList || '')
            .split(',')
            .map((f) => f.trim())
            .filter((f) => API_NAME.test(f));
    }

    get mode() {
        return this.recordId ? 'edit' : 'new';
    }

    handleFocus(event) {
        const field = event.currentTarget.dataset.field;
        if (!field || field === this.lastField) {
            return;
        }
        this.lastField = field;
        publish(this.messageContext, GUIDEPILOT_CONTEXT, {
            objectApiName: this.object,
            recordId: this.recordId || null,
            mode: this.mode,
            fieldApiName: field
        });
    }

    handleSuccess() {
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
    }
}
