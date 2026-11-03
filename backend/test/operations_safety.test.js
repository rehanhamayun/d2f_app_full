import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';
import { TERMS_VERSION } from '../src/connect_declaration.js';

test('operational safety: maritime events, private templates, declarations and payment evidence',async t=>{
 const suffix=randomUUID(),prefix=`S${suffix.replaceAll('-','').slice(0,4).toUpperCase()}`;
 const org=await prisma.organization.create({data:{name:`Operations safety ${suffix}`,trackingPrefix:prefix}});
 const foreign=await prisma.organization.create({data:{name:`Other safety ${suffix}`,trackingPrefix:`F${suffix.replaceAll('-','').slice(0,4).toUpperCase()}`}});
 const origin=await prisma.location.create({data:{organizationId:org.id,name:'Omaha Warehouse',code:'OMA',city:'Omaha',country:'United States',address:'D2F public warehouse',connectReceiving:true}});
 const dest=await prisma.location.create({data:{organizationId:org.id,name:'Lomé Warehouse',code:'LOM',city:'Lomé',country:'Togo',address:'D2F destination warehouse',connectReceiving:true}});
 const makeUser=(name,role,organizationId=org.id,locationId=origin.id)=>prisma.user.create({data:{email:`${name}-${suffix}@example.test`,passwordHash:'test-only',fullName:name,role,phone:'+14025550123',organizationId,locationId:organizationId===org.id?locationId:null}});
 const admin=await makeUser('Safety Admin','ADMIN'),staff=await makeUser('Safety Staff','STAFF'),customer=await makeUser('Safety Customer','CUSTOMER'),stranger=await makeUser('Unrelated Customer','CUSTOMER'),traveller=await makeUser('Safety Traveller','CUSTOMER'),otherAdmin=await makeUser('Other Admin','ADMIN',foreign.id);
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));const base=`http://127.0.0.1:${server.address().port}`;
 const token=u=>jwt.sign({id:u.id,purpose:'session',ver:0},JWT_SECRET);
 const call=async(path,who=admin,body,method=body?'POST':'GET')=>{const r=await fetch(base+path,{method,headers:{Authorization:`Bearer ${token(who)}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,body:await r.json()};};
 const ok=async(...args)=>{const r=await call(...args);assert.ok(r.status>=200&&r.status<300,`${args[0]} ${r.status}: ${JSON.stringify(r.body)}`);return r.body;};
 const image=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=','base64');
 let parcel,container,booking,template;
 const createBooking=async(reverse=false)=>ok('/connect/bookings',customer,{origin:reverse?'Lomé, Togo':'Omaha, USA',destination:reverse?'Omaha, USA':'Lomé, Togo',description:'3 cotton shirts; 2 pairs of shoes; no batteries.',category:'CLOTHING',quantity:5,weightKg:3,declaredValueMinor:10000,recipientName:'Recipient Person',recipientPhone:'+22890001122',recipientAddress:'Declared destination address',senderCity:'Omaha',senderAddress:'Private sender address',handoverMode:'DROP_OFF',deliveryPreference:'D2F_PICKUP',preferredDate:new Date(Date.now()+86400000).toISOString(),restrictionsAcknowledged:true,clientRequestId:randomUUID()});
 const declaration=(contents,changes={})=>({legalName:'Safety Customer',contents,termsVersion:TERMS_VERSION,checks:[true,true,true,true,true],electronicAcknowledgment:true,...changes});
 const review={approved:true,verifiedWeightKg:3,note:'Staff physical contents inspection and route documents verified.',declarationReviewed:true,inspectionConfirmed:true,restrictionsChecked:true};
 const proof=async(b,who=customer,version=1,accepted='true',bytes=image)=>{
  const r=await fetch(`${base}/connect/bookings/${b.id}/payment-submissions?method=MOBILE_MONEY&instructionsVersion=${version}&accepted=${accepted}&transactionId=TX-${suffix}`,{method:'POST',headers:{Authorization:`Bearer ${token(who)}`,'Content-Type':'image/png'},body:bytes});return {status:r.status,body:await r.json()};
 };
 try{
  await t.test('receipt provides status-specific templates; custom details remain private and original notes survive corrections',async()=>{
   const c=await ok('/customers',admin,{displayName:'Safety Shipper'});
   parcel=await ok('/parcels',staff,{customerId:c.id,recipientName:'Receiver',packageType:'BOX',weightKg:3,origin:'Omaha, USA',destination:'Lomé, Togo',method:'SEA',clientRequestId:randomUUID()});
   // Staff registration represents intake, but verify legacy custody explicitly.
   await prisma.parcel.update({where:{id:parcel.id},data:{warehouseReceivedAt:null}});
   const rows=await ok('/operational-notes?status=RECEIVED&serviceType=SEA',staff);template=rows.find(r=>r.status==='RECEIVED');assert.ok(template);
   assert.ok(rows.every(r=>['RECEIVED','EXCEPTION'].includes(r.status)));
   assert.equal((await call('/operational-notes',customer)).status,403);
   assert.equal((await call('/operational-notes',staff,{status:'RECEIVED'})).status,403);
   assert.equal((await call(`/operational-notes/${template.id}`,otherAdmin,{...template,message:'Foreign edit'},'PATCH')).status,404);
   const intake={locationId:origin.id,confirmed:true,scannedTrackingId:parcel.trackingId,verifiedItemIds:[],noteTemplateId:template.id,additionalDetails:'PRIVATE-INSPECTION-DETAIL'};
   assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,staff,{...intake,noteTemplateId:null})).status,400);
   const received=await ok(`/parcels/${parcel.id}/warehouse-intake`,staff,intake);assert.equal(received.facilityId,origin.id);assert.equal(received.actorId,staff.id);assert.match(received.internalNote,/PRIVATE-INSPECTION/);assert.ok(!received.note.includes('PRIVATE'));
   const corrected=await ok(`/parcels/${parcel.id}/events/${received.id}/note`,staff,{note:'PRIVATE corrected inspection details'},'PATCH');assert.match(corrected.originalNote,/PRIVATE-INSPECTION/);assert.equal(corrected.note,received.note);
   assert.equal(await prisma.auditLog.count({where:{entityId:parcel.id,action:'PARCEL_EVENT_NOTE_EDIT'}}),1);
   await ok(`/operational-notes/${template.id}`,admin,{...template,isActive:false},'PATCH');
   assert.ok(!(await ok('/operational-notes?status=RECEIVED&serviceType=SEA',staff)).some(t=>t.id===template.id));
   const processing=await ok('/operational-notes?status=PROCESSING&serviceType=SEA',staff);
   assert.equal((await call(`/parcels/${parcel.id}/events`,staff,{status:'PROCESSING',locationId:origin.id,noteTemplateId:template.id})).status,400);
   await ok(`/parcels/${parcel.id}/events`,staff,{status:'PROCESSING',locationId:origin.id,noteTemplateId:processing.find(t=>t.status==='PROCESSING').id,additionalDetails:'PRIVATE-PROCESSING'});
  });
  await t.test('sea parcels cannot depart manually or load before staging; container events atomically preserve physical order',async()=>{
   const early=await call(`/parcels/${parcel.id}/events`,staff,{status:'IN_TRANSIT',locationId:origin.id,confirmed:true});assert.equal(early.status,409);
   container=await ok('/warehouse/containers',admin,{code:`SAFE-${suffix.slice(0,8)}`,originId:origin.id,destinationId:dest.id,method:'SEA'});
   assert.equal((await call(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId,loadingConfirmed:true})).status,409);
   assert.equal((await call(`/parcels/${parcel.id}/events`,staff,{status:'READY_FOR_LOADING',locationId:origin.id,customMessage:'Container departure confirmed.'})).status,400);
   await ok(`/parcels/${parcel.id}/events`,staff,{status:'READY_FOR_LOADING',locationId:origin.id,customMessage:'Parcel verified and approved for loading.'});
   assert.equal((await call(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId})).status,400);
   await ok(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId,loadingConfirmed:true});
   let p=await ok(`/parcels/${parcel.id}`,staff);assert.equal(p.status,'LOADED_IN_CONTAINER');assert.equal(p.container.code,container.code);
   assert.equal((await call(`/warehouse/containers/${container.id}/events`,admin,{action:'DEPARTED'})).status,400);
   assert.equal((await call(`/warehouse/containers/${container.id}/events`,admin,{action:'ARRIVED',confirmed:true})).status,409);
   const races=await Promise.all([1,2].map(()=>call(`/warehouse/containers/${container.id}/events`,admin,{action:'DEPARTED',confirmed:true})));assert.deepEqual(races.map(r=>r.status).sort(),[201,409]);
   await ok(`/warehouse/containers/${container.id}/events`,admin,{action:'ARRIVED',confirmed:true});p=await ok(`/parcels/${parcel.id}`,staff);assert.equal(p.status,'ARRIVED_PORT');
   assert.equal((await call(`/parcels/${parcel.id}/events`,admin,{status:'READY_FOR_PICKUP',locationId:dest.id,confirmed:true})).status,400);
   for(const [action,status] of [['CUSTOMS_CLEARANCE','CUSTOMS_CLEARANCE'],['CUSTOMS_CLEARED','CUSTOMS_CLEARED'],['ARRIVED','RECEIVED_DESTINATION']]){await ok(`/warehouse/containers/${container.id}/events`,admin,{action,confirmed:true});assert.equal((await ok(`/parcels/${parcel.id}`,staff)).status,status);}
   await ok(`/parcels/${parcel.id}/events`,admin,{status:'READY_FOR_PICKUP',locationId:dest.id,confirmed:true});
   p=await ok(`/parcels/${parcel.id}`,staff);assert.ok(p.events.filter(e=>['LOADED_IN_CONTAINER','IN_TRANSIT','ARRIVED_PORT','CUSTOMS_CLEARANCE','CUSTOMS_CLEARED','RECEIVED_DESTINATION'].includes(e.status)).every(e=>e.actorId&&e.facilityId&&e.createdAt));
   assert.equal((await call(`/parcels/${parcel.id}/reconcile-sea-departure`,admin,{reason:'cannot rewind a departed manifest',confirmed:true,locationId:origin.id})).status,409);
  });
  await t.test('customer declaration is manual, versioned, route-aware and distinct from staff approval',async()=>{
   booking=await createBooking();
   assert.equal((await call(`/connect/bookings/${booking.id}/review`,staff,review)).status,409);
   const policy=await ok(`/connect/bookings/${booking.id}/declaration-policy`,customer);assert.equal(policy.checks.length,5);assert.ok(policy.guidance.some(g=>g.title==='Entering Togo'));assert.ok(policy.guidance.some(g=>g.title==='Leaving the United States'));
   for(const changes of [{checks:[true,true,true,true,false]},{termsVersion:'obsolete'},{electronicAcknowledgment:false},{legalName:''}])assert.equal((await call(`/connect/bookings/${booking.id}/declarations`,customer,declaration(booking.parcel.notes,changes))).status,400);
   assert.equal((await call(`/connect/bookings/${booking.id}/declarations`,staff,declaration(booking.parcel.notes))).status,403);
   assert.equal((await call(`/connect/bookings/${booking.id}/declarations`,stranger,declaration(booking.parcel.notes))).status,404);
   let ack=await ok(`/connect/bookings/${booking.id}/declarations`,customer,declaration(booking.parcel.notes));assert.equal(ack.contentsVerifiedAt,null);assert.ok(!ack.declarations[0].audit);assert.equal(ack.declarations[0].bookingId,booking.id);assert.equal(ack.declarations[0].customerId,ack.parcel.customerId);
   assert.equal((await call(`/connect/bookings/${booking.id}/review`,staff,{...review,inspectionConfirmed:false})).status,400);
   let reviewed=await ok(`/connect/bookings/${booking.id}/review`,staff,review);assert.equal(reviewed.reviewedDeclarationId,ack.declarations[0].id);assert.ok(reviewed.declarations[0].audit.ip);
   ack=await ok(`/connect/bookings/${booking.id}/declarations`,customer,declaration('4 cotton shirts; 2 pairs of shoes; no batteries.'));assert.equal(ack.declarations.length,2);assert.equal(ack.contentsVerifiedAt,null);assert.equal(ack.reviewedDeclarationId,null);assert.equal(ack.parcel.status,'UNDER_REVIEW');
   assert.equal((await call(`/connect/bookings/${booking.id}/receive`,staff,{note:'Not yet reviewed'})).status,409);
   await ok(`/connect/bookings/${booking.id}/review`,staff,review);
   const reverse=await createBooking(true),reversePolicy=await ok(`/connect/bookings/${reverse.id}/declaration-policy`,customer);assert.ok(reversePolicy.guidance.some(g=>g.title==='Entering the United States'));assert.ok(reversePolicy.guidance.some(g=>g.title==='Leaving Togo'));
   assert.equal((await call(`/connect/bookings/${booking.id}`,otherAdmin)).status,404);
  });
  await t.test('payment evidence requires latest instructions, ownership and a screenshot; verification never changes physical status',async()=>{
   await ok(`/connect/bookings/${booking.id}/quote`,admin,{internationalFeeMinor:5000,domesticCostMinor:0,note:'Verified quote'});
   await ok(`/connect/bookings/${booking.id}/accept-quote`,customer,{totalMinor:5000});
   assert.equal((await proof(booking)).status,409);
   await ok(`/connect/bookings/${booking.id}/payment-instructions`,admin,{instructions:'Use D2F verified mobile money instructions with booking reference.'});
   assert.equal((await proof(booking,stranger)).status,404);assert.equal((await proof(booking,customer,1,'false')).status,409);assert.equal((await proof(booking,customer,0)).status,409);assert.equal((await proof(booking,customer,1,'true',Buffer.from('not an image'))).status,400);
   assert.equal((await call(`/connect/bookings/${booking.id}/payment`,admin,{reference:'UNVERIFIED',amountMinor:5000})).status,409);
   let submitted=await proof(booking);assert.equal(submitted.status,201,JSON.stringify(submitted.body));assert.equal(submitted.body.payment,null);assert.equal(submitted.body.paymentSubmissions[0].status,'PENDING');assert.ok(!JSON.stringify(submitted.body).includes('"bytes"'));
   let sub=submitted.body.paymentSubmissions[0];const path=`/connect/bookings/${booking.id}/payment-submissions/${sub.id}/image`;
   for(const [who,status] of [[customer,200],[staff,200],[stranger,404],[otherAdmin,404]]){const r=await fetch(base+path,{headers:{Authorization:`Bearer ${token(who)}`}});assert.equal(r.status,status);if(status===200){assert.equal(r.headers.get('cache-control'),'private, no-store');assert.deepEqual(Buffer.from(await r.arrayBuffer()),image);}}
   await ok(`/connect/bookings/${booking.id}/payment-submissions/${sub.id}/reject`,admin,{note:'Please attach the complete transaction receipt.'});
   assert.equal((await proof(booking)).status,201);
   await ok(`/connect/bookings/${booking.id}/payment-instructions`,admin,{instructions:'Updated verified D2F payment instructions.'});assert.equal((await proof(booking)).status,409);assert.equal((await proof(booking,customer,2)).status,201);
   const before=await ok(`/connect/bookings/${booking.id}`,customer);
   const paid=await ok(`/connect/bookings/${booking.id}/payment`,admin,{reference:`VERIFIED-${suffix}`,amountMinor:5000});assert.equal(paid.parcel.status,before.parcel.status);assert.ok(paid.payment);assert.ok(paid.paymentSubmissions.some(s=>s.status==='VERIFIED'));assert.ok(paid.paymentSubmissions.some(s=>s.status==='SUPERSEDED'));
   assert.ok(!JSON.stringify(await ok(`/connect/bookings/${booking.id}`,customer)).includes('userAgent'));
  });
 }finally{
  await new Promise(r=>server.close(r));
  const ids=(await prisma.parcel.findMany({where:{organizationId:org.id},select:{id:true}})).map(p=>p.id),bids=(await prisma.connectBooking.findMany({where:{organizationId:org.id},select:{id:true}})).map(b=>b.id);
  await prisma.connectDeclaration.deleteMany({where:{bookingId:{in:bids}}});await prisma.connectPaymentSubmission.deleteMany({where:{bookingId:{in:bids}}});await prisma.connectPayment.deleteMany({where:{organizationId:org.id}});await prisma.connectAssignment.deleteMany({where:{bookingId:{in:bids}}});await prisma.connectBooking.deleteMany({where:{organizationId:org.id}});
  await prisma.trackingEvent.deleteMany({where:{parcelId:{in:ids}}});await prisma.trackingIndex.deleteMany({where:{parcelId:{in:ids}}});await prisma.parcelItem.deleteMany({where:{parcelId:{in:ids}}});await prisma.parcel.deleteMany({where:{id:{in:ids}}});await prisma.containerEvent.deleteMany({where:{container:{organizationId:org.id}}});await prisma.container.deleteMany({where:{organizationId:org.id}});await prisma.customer.deleteMany({where:{organizationId:org.id}});await prisma.user.deleteMany({where:{organizationId:{in:[org.id,foreign.id]}}});await prisma.location.deleteMany({where:{organizationId:org.id}});await prisma.operationalNoteTemplate.deleteMany({where:{organizationId:org.id}});await prisma.organization.deleteMany({where:{id:{in:[org.id,foreign.id]}}});await prisma.$disconnect();
 }
});
