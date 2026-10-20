import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import { prisma } from '../src/db.js';
import { JWT_SECRET } from '../src/config.js';

// Runs against the configured local test database. Only its own fixtures are removed.
test('M1: authentication, permissions, concurrent retries, tracking and history', async (t) => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const createdParcels = [], createdUsers = [];
  let customer;
  const request = async (path, {token, method='GET', data}={}) => {
    const response = await fetch(`${base}${path}`, {method,
      headers: {'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})},
      ...(data ? {body:JSON.stringify(data)} : {}),
    });
    return {status:response.status, body:await response.json()};
  };
  try {
    const staff = await prisma.user.findUniqueOrThrow({where:{email:'staff@d2fshipping.com'}});
    const token = jwt.sign({id:staff.id,role:'STAFF'},JWT_SECRET);
    const suffix = randomUUID();
    customer = await prisma.customer.create({data:{displayName:`M1 automated QA ${suffix}`}});
    const input = {customerId:customer.id,recipientName:'M1 isolated test recipient',packageType:'BOX',weightKg:2.5,
      origin:'Omaha, NE, USA',destination:'Lomé, Togo',method:'SEA',clientRequestId:`qa-${suffix}`};

    await t.test('health verifies database and unauthenticated reads are rejected', async()=>{
      assert.equal((await request('/health')).body.database,'connected');
      assert.equal((await request('/parcels')).status,401);
      assert.equal((await request('/customers')).status,401);
      assert.equal((await request('/auth/login',{method:'POST',data:{email:staff.email,password:'incorrect-password'}})).status,401);
    });
    await t.test('non-staff and disabled accounts cannot read operational records',async()=>{
      for (const role of ['CUSTOMER','DRIVER']) {
        const user=await prisma.user.create({data:{email:`${role}-${suffix}@example.com`,fullName:'QA role fixture',passwordHash:'unused',role}});
        createdUsers.push(user.id);
        const restricted=jwt.sign({id:user.id,role:'STAFF'},JWT_SECRET); // DB role must override a stale role claim.
        for(const path of ['/parcels','/parcels/stats','/customers']) assert.equal((await request(path,{token:restricted})).status,403);
      }
      const user=await prisma.user.create({data:{email:`disabled-${suffix}@example.com`,fullName:'QA disabled fixture',passwordHash:'unused',role:'STAFF',isActive:false}});
      createdUsers.push(user.id);
      assert.equal((await request('/parcels',{token:jwt.sign({id:user.id,role:'STAFF'},JWT_SECRET)})).status,401);
    });
    await t.test('profile edits persist without allowing role or email changes',async()=>{
      const user=await prisma.user.create({data:{email:`profile-${suffix}@example.com`,fullName:'QA profile fixture',passwordHash:'unused',role:'STAFF'}});
      createdUsers.push(user.id);
      const ownToken=jwt.sign({id:user.id,role:'STAFF'},JWT_SECRET);
      assert.equal((await request('/auth/me',{method:'PATCH',data:{fullName:'Unauthorized'}})).status,401);
      assert.equal((await request('/auth/me',{token:ownToken,method:'PATCH',data:{fullName:' '}})).status,400);
      const result=await request('/auth/me',{token:ownToken,method:'PATCH',data:{fullName:'Updated profile',phone:'+1 402 555 0100',role:'ADMIN',email:'other@example.com'}});
      assert.equal(result.status,200);assert.equal(result.body.user.role,'STAFF');assert.equal(result.body.user.email,user.email);
      const saved=(await request('/auth/me',{token:ownToken})).body.user;
      assert.equal(saved.fullName,'Updated profile');assert.equal(saved.phone,'+1 402 555 0100');
    });
    let parcel;
    await t.test('concurrent retries create exactly one parcel with a stable UUID and tracking ID',async()=>{
      const results=await Promise.all(Array.from({length:3},()=>request('/parcels',{token,method:'POST',data:input})));
      for(const result of results) assert.ok([200,201].includes(result.status),JSON.stringify(result.body));
      const ids=new Set(results.map(r=>r.body.id));
      assert.equal(ids.size,1);
      parcel=results[0].body;createdParcels.push(parcel.id);
      assert.match(parcel.id,/^[\da-f-]{36}$/i);assert.match(parcel.trackingId,/^D2F-\d{4}-\d{6}$/);
      assert.equal(await prisma.parcel.count({where:{clientRequestId:input.clientRequestId}}),1);
      const found=await request(`/parcels/${parcel.trackingId}`,{token});
      assert.equal(found.body.id,parcel.id);assert.equal(found.body.events.length,1);
      assert.equal(found.body.events[0].actor.fullName,staff.fullName);
    });
    await t.test('simultaneous distinct parcels receive unique tracking IDs',async()=>{
      const results=await Promise.all(Array.from({length:3},(_,i)=>request('/parcels',{token,method:'POST',data:{...input,clientRequestId:`qa-${suffix}-${i}`}})));
      for(const result of results) { assert.equal(result.status,201,JSON.stringify(result.body));createdParcels.push(result.body.id); }
      assert.equal(new Set(results.map(r=>r.body.trackingId)).size,3);
    });
    await t.test('concurrent status updates record one event; backward transitions are rejected',async()=>{
      const results=await Promise.all(Array.from({length:2},()=>request(`/parcels/${parcel.id}/events`,{token,method:'POST',data:{status:'PROCESSING',location:'Omaha Warehouse',note:'Prepared for shipment'}})));
      assert.equal(results.filter(r=>r.status===201).length,1);
      assert.ok(results.some(r=>[400,409].includes(r.status)));
      assert.equal((await request(`/parcels/${parcel.id}/events`,{token,method:'POST',data:{status:'RECEIVED'}})).status,400);
      const saved=(await request(`/parcels/${parcel.trackingId}`,{token})).body;
      assert.equal(saved.status,'PROCESSING');assert.equal(saved.events.length,2);
      assert.equal(saved.events[1].note,'Prepared for shipment');assert.equal(saved.events[1].location,'Omaha Warehouse');
      assert.ok(saved.events.every(e=>e.createdAt&&e.actor));
    });
  } finally {
    await prisma.auditLog.deleteMany({where:{entityId:{in:createdParcels}}});
    await prisma.trackingEvent.deleteMany({where:{parcelId:{in:createdParcels}}});
    await prisma.trackingIndex.deleteMany({where:{parcelId:{in:createdParcels}}});
    await prisma.parcel.deleteMany({where:{id:{in:createdParcels}}});
    if(customer) await prisma.customer.delete({where:{id:customer.id}});
    await prisma.user.deleteMany({where:{id:{in:createdUsers}}});
    await new Promise(resolve=>server.close(resolve));
    await prisma.$disconnect();
  }
});
