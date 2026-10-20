import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  // ── Organization + locations ──────────────────────────────────────────────
  const org = await prisma.organization.upsert({
    where: { id: 'org-d2f' },
    update: {},
    create: { id: 'org-d2f', name: 'D2F Shipping LLC' },
  });

  const omaha = await prisma.location.upsert({
    where: { organizationId_code: { organizationId: org.id, code: 'OMA-1' } },
    update: {},
    create: {
      organizationId: org.id,
      name: 'Omaha Warehouse',
      code: 'OMA-1',
      city: 'Omaha, NE',
      country: 'United States',
      timezone: 'America/Chicago',
    },
  });

  await prisma.location.upsert({
    where: { organizationId_code: { organizationId: org.id, code: 'LOME-1' } },
    update: {},
    create: {
      organizationId: org.id,
      name: 'Lomé Facility',
      code: 'LOME-1',
      city: 'Lomé',
      country: 'Togo',
      timezone: 'Africa/Lome',
    },
  });

  // ── Users ─────────────────────────────────────────────────────────────────
  const staffPassword = process.env.DEMO_STAFF_PASSWORD || (process.env.NODE_ENV !== 'production' ? 'Staff@2026' : null);
  const adminPassword = process.env.DEMO_ADMIN_PASSWORD || (process.env.NODE_ENV !== 'production' ? 'Admin@2026' : null);
  if (!staffPassword || !adminPassword) throw new Error('Set DEMO_STAFF_PASSWORD and DEMO_ADMIN_PASSWORD for the hosted test environment.');
  const staffHash = await bcrypt.hash(staffPassword, 10);
  const adminHash = await bcrypt.hash(adminPassword, 10);

  await prisma.user.upsert({
    where: { email: 'staff@d2fshipping.com' },
    update: {},
    create: {
      email: 'staff@d2fshipping.com',
      passwordHash: staffHash,
      fullName: 'Warehouse Staff',
      role: 'STAFF',
      organizationId: org.id,
      locationId: omaha.id,
    },
  });

  await prisma.user.upsert({
    where: { email: 'admin@d2fshipping.com' },
    update: {},
    create: {
      email: 'admin@d2fshipping.com',
      passwordHash: adminHash,
      fullName: 'D2F Admin',
      role: 'ADMIN',
      organizationId: org.id,
      locationId: omaha.id,
    },
  });

  // ── Sample customers ──────────────────────────────────────────────────────
  const koffi = await prisma.customer.upsert({
    where: { id: 'cust-koffi-demo' },
    update: {},
    create: {
      id: 'cust-koffi-demo',
      displayName: 'Koffi Mensah',
      email: 'koffi.mensah@example.com',
      phone: '+228 90 12 34 56',
      address: '12 Route d’Aného',
      city: 'Lomé',
      country: 'Togo',
    },
  });

  await prisma.customer.upsert({
    where: { id: 'cust-fatima-demo' },
    update: {},
    create: {
      id: 'cust-fatima-demo',
      displayName: 'Fatima Okoye',
      email: 'fatima.okoye@example.com',
      phone: '+1 402 555 0142',
      address: '88 Leavenworth St',
      city: 'Omaha, NE',
      country: 'United States',
    },
  });

  // ── Sample parcels (real backend data for acceptance demo) ───────────────
  const staff = await prisma.user.findUnique({ where: { email: 'staff@d2fshipping.com' } });

  const sampleParcels = [
    {
      trackingId: 'D2F-2026-000101',
      customer: koffi,
      recipientName: 'Aïcha Tetteh',
      recipientPhone: '+228 91 88 77 66',
      recipientAddress: '45 Boulevard du Mono, Lomé',
      packageType: 'BOX',
      weightKg: 2.5,
      origin: 'Omaha, NE, USA',
      destination: 'Lomé, Togo',
      method: 'AIR',
      status: 'IN_TRANSIT',
      daysAgo: 6,
      events: [
        { status: 'RECEIVED', note: 'Parcel registered at intake', location: 'Omaha, NE, USA', daysAgo: 6 },
        { status: 'PROCESSING', note: 'Sorted and prepared for shipment', location: 'Omaha, NE, USA', daysAgo: 5 },
        { status: 'IN_TRANSIT', note: 'Departed Omaha', location: 'Omaha, NE, USA', daysAgo: 4 },
      ],
    },
    {
      trackingId: 'D2F-2026-000102',
      customer: koffi,
      recipientName: 'Koffi Mensah Jr.',
      recipientPhone: '+228 90 12 34 56',
      recipientAddress: '12 Route d’Aného, Lomé',
      packageType: 'BARREL',
      weightKg: 22.0,
      origin: 'Omaha, NE, USA',
      destination: 'Lomé, Togo',
      method: 'SEA',
      status: 'READY_FOR_PICKUP',
      daysAgo: 12,
      events: [
        { status: 'RECEIVED', note: 'Parcel registered at intake', location: 'Omaha, NE, USA', daysAgo: 12 },
        { status: 'PROCESSING', note: 'Loaded into container', location: 'Omaha, NE, USA', daysAgo: 11 },
        { status: 'IN_TRANSIT', note: 'Departed Omaha', location: 'Omaha, NE, USA', daysAgo: 10 },
        { status: 'ARRIVED_LOME', note: 'Arrived at Lomé facility', location: 'Lomé, Togo', daysAgo: 2 },
        { status: 'READY_FOR_PICKUP', note: 'Ready for customer pickup', location: 'Lomé, Togo', daysAgo: 1 },
      ],
    },
    {
      trackingId: 'D2F-2026-000103',
      customer: koffi,
      recipientName: 'Mariam Diallo',
      recipientPhone: '+226 70 22 33 44',
      recipientAddress: 'Sector 15, Ouagadougou',
      packageType: 'DOCUMENTS',
      weightKg: 0.4,
      origin: 'Omaha, NE, USA',
      destination: 'Ouagadougou, Burkina Faso',
      method: 'AIR',
      status: 'DELIVERED',
      daysAgo: 20,
      events: [
        { status: 'RECEIVED', note: 'Parcel registered at intake', location: 'Omaha, NE, USA', daysAgo: 20 },
        { status: 'PROCESSING', note: 'Sorted and prepared', location: 'Omaha, NE, USA', daysAgo: 19 },
        { status: 'IN_TRANSIT', note: 'Departed Omaha', location: 'Omaha, NE, USA', daysAgo: 18 },
        { status: 'ARRIVED_LOME', note: 'Arrived at Lomé transit hub', location: 'Lomé, Togo', daysAgo: 15 },
        { status: 'READY_FOR_PICKUP', note: 'Out for road delivery', location: 'Lomé, Togo', daysAgo: 14 },
        { status: 'DELIVERED', note: 'Delivered to recipient', location: 'Ouagadougou, Burkina Faso', daysAgo: 13 },
      ],
    },
  ];

  for (const sp of sampleParcels) {
    const exists = await prisma.parcel.findUnique({ where: { trackingId: sp.trackingId } });
    if (exists) continue;

    const created = await prisma.parcel.create({
      data: {
        trackingId: sp.trackingId,
        customerId: sp.customer.id,
        recipientName: sp.recipientName,
        recipientPhone: sp.recipientPhone,
        recipientAddress: sp.recipientAddress,
        packageType: sp.packageType,
        weightKg: sp.weightKg,
        origin: sp.origin,
        destination: sp.destination,
        method: sp.method,
        status: sp.status,
        createdById: staff.id,
        locationId: omaha.id,
      },
    });

    await prisma.trackingIndex.create({
      data: { trackingId: sp.trackingId, parcelId: created.id },
    });

    for (const ev of sp.events) {
      await prisma.trackingEvent.create({
        data: {
          parcelId: created.id,
          status: ev.status,
          note: ev.note,
          location: ev.location,
          actorId: staff.id,
          createdAt: new Date(Date.now() - ev.daysAgo * 86400000),
        },
      });
    }
  }

  console.log('Seed complete: users, locations, customers, sample parcels.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
