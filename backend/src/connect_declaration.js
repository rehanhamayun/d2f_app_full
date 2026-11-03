import { createHash } from 'node:crypto';
import { fail, routeKey } from './connect_rules.js';
export const TERMS_VERSION = 'D2F-CONTENTS-2026-11-02-v1';
export const DECLARATION_WARNING = 'Prohibited, illegal, dangerous, concealed or falsely declared items may be confiscated and may lead to fines or criminal prosecution under applicable law. Declare every item accurately. Customer acknowledgment is not an inspection, safety certification or D2F approval.';
export const DECLARATION_CHECKS = [
 'I accurately declare all contents, quantities and relevant details.',
 'The package contains no prohibited items and no restricted items without required authorization.',
 'I consent to lawful inspection and verification by D2F and competent authorities.',
 'I understand that violations may result in confiscation, fines or criminal prosecution under applicable law.',
 'I accept responsibility for my declaration and accept the displayed D2F shipping terms.'
];
export const DECLARATION_TERMS = 'D2F may refuse undeclared, unsafe or unauthorized goods. You must provide complete, truthful contents and any required documents, permits or invoices. You authorize lawful inspection and verification; you remain responsible for accurate declarations and compliance with applicable origin, transit, destination and carrier requirements. Acceptance is subject to a separate D2F staff review and does not waive rights or obligations under applicable law. Any change to declared contents requires a new acknowledgment before acceptance or traveller handover.';
export function guidanceFor(origin, destination) {
 const guidance = [ { title: 'All routes', message: 'Do not send illegal drugs, weapons, explosives, flammables, concealed goods or counterfeit items. Medicines, food, plants, animal products, batteries and other controlled goods require route-specific review and any applicable permits. D2F must verify origin, transit, destination and airline rules before acceptance.' },
 { title: 'Air traveller baggage', message: 'Declare every battery and electronic device. Damaged or recalled batteries are not accepted. Spare batteries and power banks have cabin-only and capacity restrictions; do not place them in a package intended for checked baggage. Airline approval and lawful transport eligibility must be checked.', source: 'https://www.faa.gov/hazmat/packsafe' } ];
 if (/unitedstates|usa/.test(routeKey(destination))) guidance.push({ title: 'Entering the United States', message: 'Declare all goods. Food, meat, plants, seeds, animal products, medicines and other restricted articles may require permits or be prohibited. Obtain CBP and relevant agency clearance before sending.', source: 'https://www.cbp.gov/travel/us-citizens/know-before-you-go/prohibited-and-restricted-items' });
 if (/unitedstates|usa/.test(routeKey(origin))) guidance.push({ title: 'Leaving the United States', message: 'Export-controlled goods, weapons, dual-use items and regulated technology require review of US export rules and any required licenses. Airline and destination restrictions also apply.', source: 'https://www.bis.gov/licensing' });
 if (/togo/.test(routeKey(destination))) guidance.push({ title: 'Entering Togo', message: 'Togo customs restrictions and import formalities apply. D2F must verify controlled goods, permits and supporting documents with customs before acceptance.', source: 'https://togotrade.gouv.tg/media/code_des_douanes_sem_2014.pdf' });
 if (/togo/.test(routeKey(origin))) guidance.push({ title: 'Leaving Togo', message: 'Togo export restrictions and customs formalities apply, together with the destination country’s import rules. Controlled goods require appropriate authorization before acceptance.', source: 'https://togotrade.gouv.tg/media/code_des_douanes_sem_2014.pdf' });
 return guidance;
}
export const contentsHash = b => createHash('sha256').update(JSON.stringify({ contents: b.parcel.notes, category: b.category, quantity: b.quantity, origin: b.parcel.origin, destination: b.parcel.destination })).digest('hex');
export function latestDeclaration(b) { return b.declarations?.[0]; }
export function requireDeclaration(b, { reviewed = false } = {}) {
 const d = latestDeclaration(b);
 if (!d || d.contentsHash !== contentsHash(b) || d.termsVersion !== TERMS_VERSION) fail(409, 'The customer must complete the current contents declaration and all acknowledgments before parcel acceptance.');
 if (reviewed && (!b.contentsVerifiedAt || b.reviewedDeclarationId !== d.id)) fail(409, 'A separate D2F staff compliance review of the current declaration is required.');
 return d;
}
