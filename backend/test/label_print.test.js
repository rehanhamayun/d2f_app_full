import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

test('print API scopes label contacts, records idempotent device reports and never changes parcel status', async () => {
 const id=randomUUID(),org=await prisma.organization.create({data:{name:`Print QA ${id}`,trackingPrefix:'P'+id.replaceAll('-','').slice(0,4).toUpperCase()}});
 const foreign=await prisma.organization.create({data:{name:`Foreign Print ${id}`,trackingPrefix:'Q'+id.replaceAll('-','').slice(0,4).toUpperCase()}});
 const create=(role,organizationId=org.id)=>prisma.user.create({data:{email:`${role}-${organizationId}-${id}@example.test`,fullName:'Print Tester',passwordHash:'test-only',role,organizationId}});
 const staff=await create('STAFF'),driver=await create('DRIVER'),customerUser=await create('CUSTOMER'),other=await create('ADMIN',foreign.id);
 const customer=await prisma.customer.create({data:{organizationId:org.id,displayName:'Print Sender',phone:'+14025550123',address:'Test address'}});
 const p=await prisma.parcel.create({data:{organizationId:org.id,createdById:staff.id,customerId:customer.id,trackingId:`PRINT-${id}`,recipientName:'Receiver',origin:'Omaha, USA',destination:'Lomé, Togo',packageType:'BOX',weightKg:2,method:'SEA',status:'REQUESTED'}});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 const call=async(path,who=staff,body)=>{const r=await fetch(`http://127.0.0.1:${server.address().port}/label-print${path}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${jwt.sign({id:who.id,purpose:'session',ver:0},JWT_SECRET)}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,body:await r.json()};};
 try{
  assert.equal((await call(`/parcels/${p.id}`,customerUser)).status,403);
  assert.equal((await call(`/parcels/${p.id}`,other)).status,404);
  assert.equal((await call(`/parcels/${p.id}`,driver)).status,404);
  const label=await call(`/parcels/${p.id}`);assert.equal(label.status,200);assert.equal(label.body.customer.phone,customer.phone);assert.ok(!('notes' in label.body));assert.ok(!('events' in label.body));
  await prisma.parcel.update({where:{id:p.id},data:{pickupDriverId:driver.id}});
  assert.equal((await call(`/parcels/${p.id}`,driver)).status,200);
  const report={parcelId:p.id,clientJobId:`test-${id}`,printerName:'Brother POC (no hardware)',labelHash:'a'.repeat(64),pages:1,status:'FAILED',message:'Synthetic test; no print sent',source:'ANDROID_BROTHER_SDK',deviceTimeMs:Date.now()};
  assert.equal((await call('/history',staff,{...report,parcelId:null})).status,400);
  assert.equal((await call('/history',staff,{...report,deviceTimeMs:null})).status,400);
  assert.equal((await call('/history',staff,{...report,status:'DELIVERED'})).status,400);
  assert.equal((await call('/history',staff,{...report,labelHash:'bad'})).status,400);
  assert.equal((await call('/history',staff,{...report,pages:0})).status,400);
  assert.equal((await call('/history',staff,report)).status,201);
  assert.equal((await call('/history',staff,report)).status,201);
  assert.equal((await call('/history',staff,{...report,labelHash:'b'.repeat(64)})).status,409);
  assert.equal((await call(`/parcels/${p.id}/history`,staff)).body.length,1);
  assert.equal((await call(`/parcels/${p.id}/history`,driver)).body.length,0);
  assert.equal((await prisma.parcel.findUnique({where:{id:p.id}})).status,'REQUESTED');
  assert.equal(await prisma.auditLog.count({where:{entityId:p.id,action:'LABEL_PRINT_DEVICE_REPORT'}}),1);
 }finally{
  await new Promise(r=>server.close(r));await prisma.labelPrintJob.deleteMany({where:{organizationId:org.id}});await prisma.auditLog.deleteMany({where:{actorId:{in:[staff.id,driver.id,customerUser.id,other.id]}}});await prisma.parcel.delete({where:{id:p.id}});await prisma.customer.delete({where:{id:customer.id}});await prisma.user.deleteMany({where:{organizationId:{in:[org.id,foreign.id]}}});await prisma.organization.deleteMany({where:{id:{in:[org.id,foreign.id]}}});await prisma.$disconnect();
 }
});
