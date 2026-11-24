export const shipForMeTerms = {
  version: 'ship-for-me-1.0',
  serviceType: 'SHIP_FOR_ME',
  title: 'D2F Ship For Me terms',
  content: `1. The service
You buy and pay for goods directly from a retailer. D2F receives the package at the assigned warehouse and arranges onward shipping after you accept the shipping quote and complete payment. The retailer handles product prices, warranties, and retailer refunds.

2. Receiving your purchase
Use the warehouse address and customer reference displayed in the D2F app. Enter the retailer, order and carrier details when you register your purchase. Keep your receipt and carrier tracking number. D2F confirms receipt after it identifies and checks the package. A retailer’s delivery scan alone does not confirm that D2F has matched the package to your account.

3. Contents and inspection
Declare the contents, quantity, condition and value accurately. You authorize D2F to open and inspect packages as reasonably needed for safety, identification, repacking, and customs documentation. Ask D2F before sending goods that may need special handling, including food, batteries, liquids, medicines or valuable goods. D2F can refuse goods that the route, carrier or applicable law prohibits or restricts.

4. Quotes, payment and customs
Review the available shipping method and the itemized quote before paying. The quote identifies D2F shipping and any applicable handling, preparation, insurance or storage charges. D2F will tell you about a material change to its charges and ask you to accept the revised quote before proceeding. Duties, taxes and customs charges apply where required. Provide complete customs documents and any requested proof of purchase. Pay using the instructions displayed by D2F.

5. Delivery, holds and returns
Delivery estimates can change due to transport interruptions, customs review or incomplete information. D2F will contact you about unresolved packages, exceptions and available return options. Any return or storage cost charged by D2F will be disclosed before it is incurred, except where applicable law requires otherwise. The retailer’s return window and conditions apply to the item itself.

6. Damage, loss and support
Report a missing, damaged or misdelivered shipment promptly to info@d2fshipping.com. Include your D2F reference, carrier tracking, receipt and photos where available. D2F will review the claim under applicable law and any coverage disclosed in your accepted shipping quote. These terms do not reduce rights that applicable law protects.

7. Information and acceptance
D2F uses purchase, shipment and contact information to identify packages, arrange delivery, meet customs obligations and respond to support requests. D2F may share information necessary for those purposes with the carrier or relevant authorities. When you select Accept, D2F records your acceptance and the version of these terms. A future version must be accepted before you register a new purchase.`,
};

export async function seedShipForMe(prisma, organizationId) {
  await prisma.$transaction(async tx => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended('customer-agreements', 0))`;
    if (!await tx.customerAgreement.count({ where: { serviceType: 'SHIP_FOR_ME' } })) {
      await tx.customerAgreement.create({ data: { ...shipForMeTerms, isActive: true } });
    }
    // D2F's published Omaha address. Existing warehouse choices take priority.
    // https://d2fshipping.com/contact/
    if (!await tx.warehouseAddress.count({ where: { organizationId } })) {
      await tx.warehouseAddress.create({ data: {
        organizationId, label: 'D2F Shipping · Omaha', addressLine1: '2658 N 90th Street',
        city: 'Omaha', stateProvince: 'NE', postalCode: '68134', country: 'United States',
        phone: '+1 402-612-6815', email: 'info@d2fshipping.com', isActive: true, isDefault: true,
      } });
    }
  });
}
