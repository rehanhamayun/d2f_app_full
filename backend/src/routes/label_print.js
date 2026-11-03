import { Router } from 'express';
import { prisma } from '../db.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { resolveOrganizationId } from '../tracking.js';
import { fail } from '../warehouse.js';
const router=Router();
router.use(authenticate,requireRole('STAFF','ADMIN','DRIVER'));
async function parcel(req,id){
 if(typeof id!=='string'||!id.trim()||id.length>160)fail(400,'Select a valid parcel before printing.');
 const organizationId=await resolveOrganizationId(prisma,req.user);
 const p=await prisma.parcel.findFirst({where:{id,organizationId,...(req.user.role==='DRIVER'?{OR:[{pickupDriverId:req.user.id},{deliveryDriverId:req.user.id}]}:{})},include:{customer:{select:{displayName:true,phone:true,address:true}},items:{orderBy:{position:'asc'}}}});
 if(!p)fail(404,'Parcel label not found or not assigned to you.');return p;
}
router.get('/parcels/:id',async(req,res,next)=>{try{const p=await parcel(req,req.params.id);res.json({id:p.id,trackingId:p.trackingId,customerId:p.customerId,recipientName:p.recipientName,recipientPhone:p.recipientPhone,recipientAddress:p.recipientAddress,pickupAddress:p.pickupAddress,origin:p.origin,destination:p.destination,method:p.method,serviceType:p.serviceType,status:p.status,packageType:p.packageType,weightKg:p.weightKg,createdAt:p.createdAt,updatedAt:p.updatedAt,customer:p.customer,items:p.items});}catch(e){next(e)}});
router.get('/parcels/:id/history',async(req,res,next)=>{try{const p=await parcel(req,req.params.id);res.json(await prisma.labelPrintJob.findMany({where:{organizationId:p.organizationId,parcelId:p.id,...(req.user.role==='DRIVER'?{actorId:req.user.id}:{})},orderBy:{createdAt:'desc'},take:200}));}catch(e){next(e)}});
router.post('/history',async(req,res,next)=>{try{
 const b=req.body||{},p=await parcel(req,b.parcelId),statuses=['COMPLETED','FAILED','UNKNOWN','QUEUED'];
 const text=(v,max)=>typeof v==='string'&&v.trim()&&v.length<=max;
 if(!text(b.clientJobId,160)||!text(b.printerName,200)||!text(b.source,40)||!['ANDROID_BROTHER_SDK','WINDOWS_LOCAL_CONNECTOR'].includes(b.source)||!statuses.includes(b.status)||!Number.isSafeInteger(b.pages)||b.pages<1||b.pages>21||typeof b.labelHash!=='string'||!/^[a-f0-9]{64}$/.test(b.labelHash)||(b.printerAddress!=null&&!text(b.printerAddress,120))||(b.message!=null&&(typeof b.message!=='string'||b.message.length>1000))||(b.reason!=null&&(typeof b.reason!=='string'||b.reason.length>500)))fail(400,'Enter a valid device-reported label print result.');
 const deviceAt=new Date(b.deviceTimeMs);if(!Number.isSafeInteger(b.deviceTimeMs)||b.deviceTimeMs<=0||!Number.isFinite(deviceAt.getTime())||deviceAt.getTime()>Date.now()+300000)fail(400,'Invalid device print time.');
 const key={organizationId:p.organizationId,actorId:req.user.id,clientJobId:b.clientJobId};
 const result=await prisma.$transaction(async tx=>{
  const old=await tx.labelPrintJob.findUnique({where:{organizationId_actorId_clientJobId:key}});
  if(old){if(old.parcelId!==p.id||old.labelHash!==b.labelHash||old.printerName!==b.printerName||old.status!==b.status)fail(409,'This print job ID is already recorded with a different result.');return old;}
  const row=await tx.labelPrintJob.create({data:{...key,parcelId:p.id,printerName:b.printerName,printerAddress:b.printerAddress||null,labelHash:b.labelHash,pages:b.pages,status:b.status,message:b.message||null,source:b.source,reason:b.reason||null,deviceAt}});
  await tx.auditLog.create({data:{actorId:req.user.id,action:'LABEL_PRINT_DEVICE_REPORT',entity:'Parcel',entityId:p.id,detail:JSON.stringify({printJobId:row.id,clientJobId:row.clientJobId,status:row.status,source:row.source,reason:row.reason,labelHash:row.labelHash,pages:row.pages})}});return row;
 });res.status(201).json(result);
}catch(e){if(e.code==='P2002')return res.status(409).json({error:'This print result is already being recorded; refresh print history.'});next(e)}});
export default router;
