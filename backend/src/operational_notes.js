import { fail } from './warehouse.js';
export const CUSTOMER_MESSAGES = {
 REQUESTED: 'Shipment request submitted; awaiting physical collection or drop-off.',
 RECEIVED: 'Parcel received at the origin warehouse.', PROCESSING: 'Parcel is being processed at the warehouse.',
 READY_FOR_LOADING: 'Parcel is ready for loading; shipment has not departed.', LOADED_IN_CONTAINER: 'Parcel loaded into its assigned container; awaiting departure.',
 IN_TRANSIT: 'Shipment departure confirmed; in transit.', ARRIVED_PORT: 'Shipment arrived at the destination port; awaiting customs clearance.',
 CUSTOMS_CLEARANCE: 'Shipment is undergoing customs clearance.', CUSTOMS_CLEARED: 'Customs release confirmed; awaiting destination warehouse receipt.',
 RECEIVED_DESTINATION: 'Parcel received at the destination warehouse.', ARRIVED_LOME: 'Parcel received at Lomé warehouse.', ARRIVED_DESTINATION: 'Parcel received at the destination facility.',
 READY_FOR_PICKUP: 'Parcel ready for pickup or delivery scheduling.', OUT_FOR_DELIVERY: 'Parcel is with the assigned delivery driver.',
 RELEASED: 'Parcel released to the authorized recipient.', DELIVERED: 'Delivery confirmed with recipient handover evidence.'
};
export const DEFAULT_NOTES = [
  {
    "status": "REQUESTED",
    "message": "Shipment request successfully submitted.",
    "serviceType": "ALL"
  },
  {
    "status": "REQUESTED",
    "message": "Awaiting customer drop-off at the warehouse.",
    "serviceType": "ALL"
  },
  {
    "status": "REQUESTED",
    "message": "Customer pickup requested; scheduling pending.",
    "serviceType": "ALL"
  },
  {
    "status": "REQUESTED",
    "message": "Awaiting domestic shipment to D2F warehouse.",
    "serviceType": "ALL"
  },
  {
    "status": "REQUESTED",
    "message": "Additional shipment information required.",
    "serviceType": "ALL"
  },
  {
    "status": "RECEIVED",
    "message": "Parcel received in good condition.",
    "serviceType": "ALL"
  },
  {
    "status": "RECEIVED",
    "message": "Parcel received and weight verified.",
    "serviceType": "ALL"
  },
  {
    "status": "RECEIVED",
    "message": "Parcel received; inspection pending.",
    "serviceType": "ALL"
  },
  {
    "status": "RECEIVED",
    "message": "Parcel received with damaged packaging.",
    "serviceType": "ALL"
  },
  {
    "status": "RECEIVED",
    "message": "Parcel received; contents require verification.",
    "serviceType": "ALL"
  },
  {
    "status": "RECEIVED",
    "message": "Parcel received and registered in warehouse inventory.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel is being processed for shipment.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel inspected and verified successfully.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel weighed and dimensions recorded.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel stored securely awaiting shipment.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel requires additional packaging.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel awaiting payment verification.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel awaiting additional documentation.",
    "serviceType": "ALL"
  },
  {
    "status": "PROCESSING",
    "message": "Parcel processing completed.",
    "serviceType": "ALL"
  },
  {
    "status": "READY_FOR_LOADING",
    "message": "Parcel verified and approved for loading.",
    "serviceType": "SEA"
  },
  {
    "status": "READY_FOR_LOADING",
    "message": "Parcel assigned to upcoming container.",
    "serviceType": "SEA"
  },
  {
    "status": "READY_FOR_LOADING",
    "message": "Parcel awaiting scheduled container loading.",
    "serviceType": "SEA"
  },
  {
    "status": "READY_FOR_LOADING",
    "message": "Parcel staged in designated loading area.",
    "serviceType": "SEA"
  },
  {
    "status": "READY_FOR_LOADING",
    "message": "Parcel held back from scheduled loading.",
    "serviceType": "SEA"
  },
  {
    "status": "LOADED_IN_CONTAINER",
    "message": "Parcel physically loaded into assigned container.",
    "serviceType": "SEA"
  },
  {
    "status": "LOADED_IN_CONTAINER",
    "message": "Parcel loading confirmed by warehouse staff.",
    "serviceType": "SEA"
  },
  {
    "status": "LOADED_IN_CONTAINER",
    "message": "Parcel loading verified against container manifest.",
    "serviceType": "SEA"
  },
  {
    "status": "READY_FOR_LOADING",
    "message": "Parcel removed from container before departure.",
    "serviceType": "SEA"
  },
  {
    "status": "IN_TRANSIT",
    "message": "Shipment departed origin facility.",
    "serviceType": "ALL"
  },
  {
    "status": "IN_TRANSIT",
    "message": "Container departure confirmed.",
    "serviceType": "SEA"
  },
  {
    "status": "IN_TRANSIT",
    "message": "Shipment is in international transit.",
    "serviceType": "ALL"
  },
  {
    "status": "IN_TRANSIT",
    "message": "Shipment transferred to connecting vessel.",
    "serviceType": "SEA"
  },
  {
    "status": "IN_TRANSIT",
    "message": "Shipment experiencing transportation delays.",
    "serviceType": "ALL"
  },
  {
    "status": "IN_TRANSIT",
    "message": "Updated estimated arrival date available.",
    "serviceType": "ALL"
  },
  {
    "status": "ARRIVED_PORT",
    "message": "Container arrived at the destination port.",
    "serviceType": "SEA"
  },
  {
    "status": "ARRIVED_PORT",
    "message": "Container awaiting port handling.",
    "serviceType": "SEA"
  },
  {
    "status": "ARRIVED_PORT",
    "message": "Container awaiting customs processing.",
    "serviceType": "SEA"
  },
  {
    "status": "ARRIVED_PORT",
    "message": "Container discharge confirmed.",
    "serviceType": "SEA"
  },
  {
    "status": "CUSTOMS_CLEARANCE",
    "message": "Shipment undergoing customs clearance.",
    "serviceType": "SEA"
  },
  {
    "status": "CUSTOMS_CLEARANCE",
    "message": "Customs documentation under review.",
    "serviceType": "SEA"
  },
  {
    "status": "CUSTOMS_CLEARANCE",
    "message": "Additional customs information required.",
    "serviceType": "SEA"
  },
  {
    "status": "CUSTOMS_CLEARANCE",
    "message": "Customs inspection in progress.",
    "serviceType": "SEA"
  },
  {
    "status": "CUSTOMS_CLEARED",
    "message": "Customs clearance completed.",
    "serviceType": "SEA"
  },
  {
    "status": "CUSTOMS_CLEARED",
    "message": "Shipment released by customs.",
    "serviceType": "SEA"
  },
  {
    "status": "RECEIVED_DESTINATION",
    "message": "Parcel received at the destination warehouse.",
    "serviceType": "SEA"
  },
  {
    "status": "RECEIVED_DESTINATION",
    "message": "Parcel unloaded and verified.",
    "serviceType": "SEA"
  },
  {
    "status": "RECEIVED_DESTINATION",
    "message": "Parcel registered in destination warehouse inventory.",
    "serviceType": "SEA"
  },
  {
    "status": "RECEIVED_DESTINATION",
    "message": "Parcel awaiting final sorting.",
    "serviceType": "SEA"
  },
  {
    "status": "RECEIVED_DESTINATION",
    "message": "Parcel discrepancy identified during unloading.",
    "serviceType": "SEA"
  },
  {
    "status": "READY_FOR_PICKUP",
    "message": "Parcel ready for customer pickup.",
    "serviceType": "ALL"
  },
  {
    "status": "READY_FOR_PICKUP",
    "message": "Customer notified of pickup availability.",
    "serviceType": "ALL"
  },
  {
    "status": "READY_FOR_PICKUP",
    "message": "Pickup appointment scheduled.",
    "serviceType": "ALL"
  },
  {
    "status": "READY_FOR_PICKUP",
    "message": "Delivery scheduled with recipient.",
    "serviceType": "ALL"
  },
  {
    "status": "READY_FOR_PICKUP",
    "message": "Parcel awaiting outstanding balance payment.",
    "serviceType": "ALL"
  },
  {
    "status": "READY_FOR_PICKUP",
    "message": "Parcel awaiting recipient confirmation.",
    "serviceType": "ALL"
  },
  {
    "status": "DELIVERED",
    "message": "Parcel released to authorized recipient.",
    "serviceType": "ALL"
  },
  {
    "status": "DELIVERED",
    "message": "Parcel successfully delivered.",
    "serviceType": "ALL"
  },
  {
    "status": "DELIVERED",
    "message": "Recipient identity verified.",
    "serviceType": "ALL"
  },
  {
    "status": "DELIVERED",
    "message": "Parcel collected at warehouse.",
    "serviceType": "ALL"
  },
  {
    "status": "DELIVERED",
    "message": "Proof of delivery recorded.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Parcel placed on hold pending investigation.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Parcel damaged; inspection required.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Parcel temporarily missing; investigation initiated.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Incorrect recipient information provided.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Customer requested shipment postponement.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Parcel reassigned to another shipment.",
    "serviceType": "ALL"
  },
  {
    "status": "EXCEPTION",
    "message": "Parcel returned to sender.",
    "serviceType": "ALL"
  },
  {
    "status": "RELEASED",
    "message": "Parcel released to authorized recipient.",
    "serviceType": "ALL"
  },
  {
    "status": "RELEASED",
    "message": "Recipient identity verified.",
    "serviceType": "ALL"
  },
  {
    "status": "RELEASED",
    "message": "Parcel collected at warehouse.",
    "serviceType": "ALL"
  },
  {
    "status": "OUT_FOR_DELIVERY",
    "message": "Parcel dispatched to the assigned delivery driver.",
    "serviceType": "ALL"
  },
  {
    "status": "ARRIVED_DESTINATION",
    "message": "Parcel received at the destination facility.",
    "serviceType": "ALL"
  },
  {
    "status": "ARRIVED_LOME",
    "message": "Parcel received at Lomé warehouse.",
    "serviceType": "ALL"
  }
];
export async function ensureNoteLibrary(tx, organizationId) {
 // Stable IDs and skipDuplicates make concurrent first loads safe. Deactivated
 // or edited defaults are never recreated or overwritten.
 await tx.operationalNoteTemplate.createMany({ data: DEFAULT_NOTES.map((n, i) => ({ ...n, id: `note:${organizationId}:${i}`, organizationId, position: i, customerMessage: CUSTOMER_MESSAGES[n.status] || 'D2F recorded a shipment exception for review.' })), skipDuplicates: true });
}
export function validateNoteMeaning(message, status) {
 const early = ['REQUESTED','RECEIVED','PROCESSING','READY_FOR_LOADING','LOADED_IN_CONTAINER'].includes(status);
 const positive = message.replace(/\b(?:has |have |is |was )?not (?:yet |been )?(?:departed|delivered)\b/gi, 'awaiting confirmation');
 if (early && /(?:has |successfully |is |was )?(?:departed|delivered)|in international transit|departure confirmed/i.test(positive)) fail(400, 'This note claims departure or delivery before the confirmed physical event. Choose a message matching the selected status.');
}
export async function resolveOperationalNote(tx, organizationId, parcel, status, body) {
 const hasSelection = body.noteTemplateId != null || body.customMessage != null;
 let internalNote, templateId = null;
 if (body.noteTemplateId) {
   const t = await tx.operationalNoteTemplate.findFirst({ where: { id: body.noteTemplateId, organizationId, isActive: true } });
   if (!t || ![status, 'EXCEPTION'].includes(t.status) || !['ALL', parcel.serviceType || parcel.method, parcel.method].includes(t.serviceType)) fail(400, 'Choose an active operational message for this status and shipping service.');
   templateId = t.id; internalNote = t.message;
 } else if (hasSelection) {
   if (typeof body.customMessage !== 'string' || !body.customMessage.trim()) fail(400, 'Enter the custom operational message.');
   internalNote = body.customMessage.trim();
 } else { internalNote = typeof body.note === 'string' ? body.note.trim() : ''; }
 if (body.additionalDetails != null && typeof body.additionalDetails !== 'string') fail(400, 'Additional details must be text.');
 if (body.additionalDetails?.trim() && !internalNote) fail(400, 'Choose a standard message before adding additional details.');
 if (body.additionalDetails?.trim()) internalNote += ` · ${body.additionalDetails.trim()}`;
 if (!internalNote && status === 'RECEIVED') fail(400, 'Select an operational message or enter Other - Custom Message.');
 if (!internalNote) internalNote = CUSTOMER_MESSAGES[status] || 'D2F recorded an operational update.';
 if (internalNote.length > 1000) fail(400, 'The operational note and additional details must total at most 1,000 characters.');
 validateNoteMeaning(internalNote, status);
 return { note: CUSTOMER_MESSAGES[status] || 'D2F recorded an operational update.', internalNote, originalNote: internalNote, templateId };
}
