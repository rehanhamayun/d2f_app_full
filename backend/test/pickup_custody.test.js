import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('pickup appointment → assigned driver custody → separately verified warehouse → container → delivery', async t => {
  const run=randomUUID(); const org=await prisma.organization.create({data:{name:'Custody QA '+run,trackingPrefix:'K'+run.replaceAll('-','').slice(0,4).toUpperCase()}});
  const origin=await prisma.location.create({data:{organizationId:org.id,name:'Omaha receiving',code:'OMA',city:'Omaha',country:'United States'}});
  const dest=await prisma.location.create({data:{organizationId:org.id,name:'Lomé receiving',code:'LOM',city:'Lomé',country:'Togo'}});
  const user=async(name,role,locationId)=>prisma.user.create({data:{email:`${name}-${run}@example.test`,fullName:name,phone:'+14025550111',passwordHash:'unused',role,organizationId:org.id,locationId}});
  const admin=await user('admin','ADMIN',origin.id),staff=await user('warehouse','STAFF',origin.id),destStaff=await user('destination','STAFF',dest.id),driver=await user('driver','DRIVER'),other=await user('other-driver','DRIVER'),customer=await user('customer','CUSTOMER');
  const token=u=>jwt.sign({id:u.id,purpose:'session',ver:0},JWT_SECRET);
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  const call=async(path,u=staff,body,method=body?'POST':'GET')=>{const r=await fetch(`http://127.0.0.1:${server.address().port}${path}`,{method,headers:{Authorization:'Bearer '+token(u),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,body:await r.json()};};
  const ok=async(...args)=>{const r=await call(...args);assert.ok(r.status>=200&&r.status<300,`${args[0]} ${r.status}: ${JSON.stringify(r.body)}`);return r.body;};
  const input=mode=>({recipientName:'Kossi',recipientPhone:'+22890001122',recipientAddress:'Lomé, Togo',packageType:'BOX',weightKg:5,origin:'Omaha, NE, USA',destination:'Lomé, Togo',method:'SEA',deliveryMode:mode,restrictionsAcknowledged:true,pickupAddress:'Customer collection address in Omaha',pickupScheduledAt:new Date(Date.now()+86400000).toISOString(),clientRequestId:randomUUID(),items:[{name:'Clothing box',quantity:2,type:'BOX'},{name:'Books',quantity:3,type:'BOX'}]});
  let parcel,container;
  const intake=()=>({locationId:origin.id,confirmed:true,note:'Physically scanned and inspected both sealed packages',scannedTrackingId:parcel.trackingId,verifiedItemIds:parcel.items.map(i=>i.id)});
  try{
    await t.test('submission records a preference without claiming an appointment or warehouse custody',async()=>{
      parcel=await ok('/customer/parcels',customer,input('PICKUP'));
      assert.ok(parcel.pickupPreferredAt);assert.equal(parcel.pickupScheduledAt,null);assert.equal(parcel.warehouseReceivedAt,null);assert.equal(parcel.status,'REQUESTED');
      const blocked=await call(`/parcels/${parcel.id}/events`,staff,{...intake(),status:'RECEIVED'});assert.equal(blocked.status,400);
      assert.equal((await call(`/parcels/${parcel.id}/pickup-schedule`,staff,{locationId:origin.id,confirmed:true,pickupScheduledAt:parcel.pickupPreferredAt})).status,400);
      assert.equal((await call(`/parcels/${parcel.id}/pickup-schedule`,staff,{locationId:dest.id,pickupDriverId:driver.id,confirmed:true,pickupScheduledAt:parcel.pickupPreferredAt})).status,400);
      await ok(`/parcels/${parcel.id}/pickup-schedule`,staff,{locationId:origin.id,pickupDriverId:driver.id,confirmed:true,pickupScheduledAt:parcel.pickupPreferredAt});
      assert.equal((await call(`/parcels/${parcel.id}/pickup-schedule`,staff,{locationId:origin.id,pickupDriverId:driver.id,confirmed:true,pickupScheduledAt:parcel.pickupPreferredAt})).status,409);
      const p=await prisma.parcel.findUnique({where:{id:parcel.id}});assert.equal(p.locationId,null);assert.equal(p.pickupDriverId,driver.id);assert.equal(p.status,'PICKUP_SCHEDULED');
    });
    await t.test('only the assigned driver can confirm physical collection, once',async()=>{
      assert.equal((await call(`/parcels/${parcel.id}/events`,admin,{status:'PICKED_UP'})).status,403);
      assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,staff,intake())).status,409);
      assert.deepEqual(await ok('/driver/tasks',other),[]);
      const tasks=await ok('/driver/tasks',driver);assert.equal(tasks.length,1);assert.equal(tasks[0].recipientAddress,null);assert.equal(tasks[0].recipientPhone,undefined);
      const body={confirmed:true,scannedTrackingId:parcel.trackingId,proofReference:'Verified sender handover REF-01'};
      assert.equal((await call(`/driver/tasks/${parcel.id}/confirm`,other,body)).status,404);
      assert.equal((await call(`/driver/tasks/${parcel.id}/confirm`,driver,{...body,scannedTrackingId:'wrong'})).status,400);
      const results=await Promise.all([1,2].map(()=>call(`/driver/tasks/${parcel.id}/confirm`,driver,body)));
      assert.deepEqual(results.map(r=>r.status).sort(),[201,404]);
      const p=await prisma.parcel.findUnique({where:{id:parcel.id}});assert.equal(p.status,'PICKED_UP');assert.equal(p.locationId,null);assert.ok(p.pickupConfirmedAt);assert.equal(p.pickupConfirmedById,driver.id);assert.equal(p.warehouseReceivedAt,null);
      assert.equal(await prisma.trackingEvent.count({where:{parcelId:p.id,status:'PICKED_UP'}}),1);
    });
    await t.test('warehouse receipt requires the actual facility, authorized staff, a scan and complete package inspection',async()=>{
      container=await ok('/warehouse/containers',staff,{code:'QA-'+run.slice(0,8),originId:origin.id,destinationId:dest.id,method:'SEA'});
      assert.equal((await call(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId,loadingConfirmed:true})).status,409);
      assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,driver,intake())).status,403);
      assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,destStaff,{...intake(),locationId:dest.id})).status,409);
      assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,staff,{...intake(),scannedTrackingId:'wrong'})).status,400);
      assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,staff,{...intake(),verifiedItemIds:[parcel.items[0].id]})).status,400);
      await ok(`/parcels/${parcel.id}/warehouse-intake`,staff,intake());
      assert.equal((await call(`/parcels/${parcel.id}/warehouse-intake`,staff,intake())).status,409);
      const p=await prisma.parcel.findUnique({where:{id:parcel.id},include:{events:{orderBy:{createdAt:'asc'}},items:true}});
      assert.equal(p.locationId,origin.id);assert.equal(p.warehouseReceivedById,staff.id);assert.ok(p.warehouseReceivedAt>=p.pickupConfirmedAt);assert.ok(p.items.every(i=>i.warehouseReceivedAt));
      assert.deepEqual(p.events.map(e=>e.status),['REQUESTED','PICKUP_SCHEDULED','PICKED_UP','RECEIVED']);assert.equal(p.events[2].actorId,driver.id);assert.equal(p.events[3].actorId,staff.id);
    });
    await t.test('loading requires verified custody and a fresh physical loading confirmation; container events retain parcel tracking',async()=>{
      assert.equal((await call(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId})).status,400);
      await ok(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId,loadingConfirmed:true});
      const retry=await ok(`/warehouse/containers/${container.id}/parcels`,staff,{trackingId:parcel.trackingId,loadingConfirmed:true});assert.equal(retry.alreadyLoaded,true);
      await ok(`/warehouse/containers/${container.id}/events`,staff,{action:'DEPARTED'});
      const manifest=await ok(`/warehouse/containers/${container.id}/manifest`,staff);assert.equal(manifest.parcels[0].trackingId,parcel.trackingId);assert.equal(manifest.provisional,false);
      await ok(`/warehouse/containers/${container.id}/events`,destStaff,{action:'ARRIVED'});
      const p=await prisma.parcel.findUnique({where:{id:parcel.id}});assert.equal(p.locationId,dest.id);assert.equal(p.trackingId,parcel.trackingId);
    });
    await t.test('out-for-delivery belongs to the assigned driver and requires recipient handover proof',async()=>{
      await ok(`/parcels/${parcel.id}/events`,destStaff,{status:'OUT_FOR_DELIVERY',locationId:dest.id,confirmed:true,deliveryDriverId:driver.id});
      const tasks=await ok('/driver/tasks',driver);assert.equal(tasks[0].pickupAddress,null);assert.equal(tasks[0].contactName,'Kossi');
      assert.equal((await call(`/parcels/${parcel.id}/events`,admin,{status:'DELIVERED',locationId:dest.id,confirmed:true,deliveredAt:new Date().toISOString(),deliveryProofType:'PHOTO',deliveryProofReference:'fake'})).status,403);
      await ok(`/driver/tasks/${parcel.id}/confirm`,driver,{confirmed:true,scannedTrackingId:parcel.trackingId,recipientName:'Kossi',proofReference:'Recipient identity checked; signed receipt REF-02'});
      assert.equal((await prisma.parcel.findUnique({where:{id:parcel.id}})).status,'DELIVERED');
      assert.equal((await ok('/driver/tasks',driver)).length,0);
    });
    await t.test('drop-off skips driver collection while legacy receipt history is retained for verification',async()=>{
      const drop=await ok('/customer/parcels',customer,input('DROP_OFF'));
      assert.equal((await call(`/parcels/${drop.id}/pickup-schedule`,staff,{pickupDriverId:driver.id,locationId:origin.id,confirmed:true,pickupScheduledAt:new Date(Date.now()+86400000).toISOString()})).status,409);
      await ok(`/parcels/${drop.id}/warehouse-intake`,staff,{...intake(),scannedTrackingId:drop.trackingId,verifiedItemIds:drop.items.map(i=>i.id)});
      const events=await prisma.trackingEvent.findMany({where:{parcelId:drop.id},orderBy:{createdAt:'asc'}});assert.deepEqual(events.map(e=>e.status),['REQUESTED','RECEIVED']);
      await prisma.parcel.update({where:{id:drop.id},data:{warehouseReceivedAt:null,warehouseReceivedById:null}});
      const original=events[1];
      await ok(`/parcels/${drop.id}/warehouse-intake`,staff,{...intake(),scannedTrackingId:drop.trackingId,verifiedItemIds:drop.items.map(i=>i.id),note:'Existing stock physically re-verified for legacy custody evidence'});
      const retained=await prisma.trackingEvent.findUnique({where:{id:original.id}});assert.equal(retained.createdAt.getTime(),original.createdAt.getTime());assert.equal(retained.note,original.note);
    });
    await t.test('legacy collected parcels receive separate driver verification without rewriting or duplicating old milestones',async()=>{
      const old=await ok('/customer/parcels',customer,input('PICKUP'));
      await prisma.parcel.update({where:{id:old.id},data:{status:'PICKED_UP'}});
      const historical=await prisma.trackingEvent.create({data:{parcelId:old.id,status:'PICKED_UP',actorId:staff.id,note:'Historical collection record'}});
      assert.equal((await call(`/parcels/${old.id}/warehouse-intake`,staff,{...intake(),scannedTrackingId:old.trackingId,verifiedItemIds:old.items.map(i=>i.id)})).status,409);
      assert.equal((await call(`/parcels/${old.id}/pickup-verification`,staff,{locationId:origin.id,pickupDriverId:driver.id,confirmed:true})).status,403);
      await ok(`/parcels/${old.id}/pickup-verification`,admin,{locationId:origin.id,pickupDriverId:driver.id,confirmed:true});
      await ok(`/driver/tasks/${old.id}/confirm`,driver,{scannedTrackingId:old.trackingId,confirmed:true,proofReference:'Original collection and driver custody verified REF-LEGACY'});
      assert.equal(await prisma.trackingEvent.count({where:{parcelId:old.id,status:'PICKED_UP'}}),1);
      assert.equal((await prisma.trackingEvent.findUnique({where:{id:historical.id}})).note,'Historical collection record');
      await ok(`/parcels/${old.id}/warehouse-intake`,staff,{...intake(),scannedTrackingId:old.trackingId,verifiedItemIds:old.items.map(i=>i.id)});
    });
  }finally{
    await new Promise(r=>server.close(r));
    const ids=(await prisma.parcel.findMany({where:{organizationId:org.id},select:{id:true}})).map(p=>p.id);
    const containers=(await prisma.container.findMany({where:{organizationId:org.id},select:{id:true}})).map(c=>c.id);
    await prisma.containerEvent.deleteMany({where:{containerId:{in:containers}}});await prisma.parcelImage.deleteMany({where:{parcelId:{in:ids}}});await prisma.parcelItem.deleteMany({where:{parcelId:{in:ids}}});await prisma.trackingEvent.deleteMany({where:{parcelId:{in:ids}}});await prisma.trackingIndex.deleteMany({where:{parcelId:{in:ids}}});await prisma.parcel.deleteMany({where:{organizationId:org.id}});await prisma.container.deleteMany({where:{organizationId:org.id}});await prisma.customer.deleteMany({where:{organizationId:org.id}});await prisma.user.deleteMany({where:{organizationId:org.id}});await prisma.location.deleteMany({where:{organizationId:org.id}});await prisma.organization.delete({where:{id:org.id}});await prisma.$disconnect();
  }
});
