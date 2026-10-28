D2F Connect – Air Traveller Module

Business Concept, Operational Workflow & Real-Life Example


I would like to explain in detail how D2F Connect (Air Traveller) works so you can understand the business logic and implement the correct workflow.

1. What Is D2F Connect?

D2F Connect is a traveller-based parcel transportation service that connects customers who want to send packages internationally with verified travellers who have available luggage capacity.

Instead of shipping packages through traditional airline cargo services using an Air Waybill (AWB), D2F Connect uses the available baggage allowance of people already travelling between supported destinations.

D2F acts as the trusted intermediary, managing parcel registration, traveller verification, matching, pricing, payments, tracking, and delivery coordination.

The three main participants are:

- Sender: A customer who wants to send a package.
- Traveller: A verified person travelling on a specific route with available luggage capacity.
- D2F Admin: The operator who supervises the transaction, verifies packages, assigns parcels, confirms payments, and coordinates delivery.

This is not simply a marketplace where strangers exchange packages without supervision. D2F maintains operational control.

2. How the Traveller System Works

Step 1 – Traveller Registration

A traveller registers and submits their travel information:

- Departure city and destination
- Travel date and flight information
- Available luggage capacity in kilograms
- Contact information
- Verification information
- Parcel categories they are willing to transport

Example:

Traveller: John

Route: Omaha, USA → Lomé, Togo

Departure: November 20, 2026

Available capacity: 15 kg

The admin reviews and approves the traveller before the trip becomes available for parcel assignments.

Step 2 – Customer Parcel Registration

A customer opens D2F Connect and registers a parcel.

The customer provides:

- Sender and recipient information
- Departure and destination
- Parcel category
- Weight and quantity
- Description and declared value
- Preferred travel date
- Pickup or delivery preferences

The system calculates the shipping price according to the configured rates.

For example, USA → Lomé:

- Clothing: $25/kg
- Phone: $60 per item
- Laptop: $100 per item
- Documents up to 500 g: $25 flat
- Documents above 500 g: Manual quotation

Prices must be configurable by the admin and may vary depending on the direction.

Step 3 – Traveller Matching

The system identifies eligible trips based on:

- Matching route and direction
- Departure date
- Available capacity
- Traveller preferences
- Allowed parcel categories
- Admin approval requirements

A parcel should never be assigned to an incompatible route or a trip without sufficient remaining capacity.

The system must distinguish between a customer's requested trip and the actual trip assigned by D2F.

Step 4 – Parcel Review and Acceptance

Before the shipment is finalized:

1. D2F reviews the parcel description and verifies its contents.
2. The traveller reviews the proposed parcel and accepts or declines it.
3. D2F confirms the final assignment.
4. The customer receives confirmation and payment instructions.
5. The parcel is handed over through an approved D2F workflow.

No parcel should be automatically considered accepted simply because a matching traveller exists.

Step 5 – Payment and Tracking

D2F manages the customer payment and records the transaction.

The system should generate a unique booking or parcel tracking number.

Customers receive notifications when important events occur, such as:

- Booking submitted
- Parcel under review
- Traveller assigned
- Payment confirmed
- Parcel received by D2F
- Parcel handed to traveller
- Traveller departed
- Parcel arrived
- Ready for pickup
- Delivered

Statuses must reflect actual confirmed events, not automatic assumptions.

3. Real-Life Example – Omaha to Lomé

Imagine the following situation.

Traveller John is flying from Omaha to Lomé on November 20, 2026.

He has 15 kg of available luggage capacity and registers his trip through D2F Connect.

Three customers want to send packages to Lomé.

Customer| Parcel| Weight| Price
Mary| Clothes| 5 kg| $125
David| Clothes| 4 kg| $100
Sarah| Laptop| 2 kg actual| $100
Total| | 11 kg| $325

The laptop is charged per item, but its actual weight still counts toward the traveller's luggage capacity.

Capacity calculation:

- Traveller capacity: 15 kg
- Assigned parcels: 11 kg
- Remaining capacity: 4 kg

The system must automatically update the remaining capacity whenever parcels are assigned, removed before departure, or their verified weight changes.

Operational scenario:

Mary registers her 5 kg clothing parcel and selects Omaha → Lomé.

D2F reviews her booking and matches it with John's trip.

John accepts the parcel after reviewing the permitted shipment information.

Mary pays $125 to D2F.

Mary delivers her parcel to the D2F Omaha collection location.

D2F verifies and records the parcel, then prepares it for handover to John.

John collects the approved parcels and travels to Lomé.

Upon arrival, John hands the parcels to the authorized D2F/Dev United receiving team.

The receiving team confirms receipt, updates the shipment status, and notifies the recipients.

Mary's recipient comes to the Lomé location, where the team verifies the recipient's identity and records the delivery confirmation.

The booking is marked Delivered only after the actual handover is confirmed.

4. Important Business Rules

Capacity management

Use the parcel's actual verified weight for capacity calculations, even when pricing is per item or flat rate.

Pricing snapshot

Once a booking quotation is accepted and confirmed, save the agreed price. Future admin price changes must not modify previously confirmed bookings.

Traveller preferences

Travellers may choose which categories they accept. Their accepted preferences should be saved for each trip and should not silently change existing confirmed assignments.

Direction validation

A traveller flying Omaha → Lomé cannot transport a parcel booked for Lomé → Omaha.

Manual quotation

Documents above 500 g and exceptional items must be sent to the admin for quotation instead of receiving an automatic price.

Security and compliance

D2F must verify parcels, reject prohibited or undeclared goods, and ensure that the traveller is legally permitted to transport the items under applicable airline, customs, and destination-country rules.

Payment control

Payment confirmations must be recorded once only, preventing duplicate transactions or repeated status changes.

Trip departure

After the traveller has departed, parcels must not be casually removed or reassigned. Any exceptional correction must be handled through an authorized admin process with an audit history.

5. D2F's Business Model

D2F collects the shipping fees from customers.

D2F may compensate travellers for transporting approved parcels according to an agreed arrangement.

The platform should therefore support:

- Customer shipping revenue
- Traveller compensation
- Payment status
- Operational expenses
- D2F profit calculation

For example:

Total customer shipping revenue: $325

Agreed traveller compensation: $150

Other operating expenses: $35

D2F estimated operating profit: $140

These compensation amounts are illustrative and should not be hardcoded.

6. Difference Between D2F Connect and Air Cargo AWB

Feature| D2F Connect| Air Cargo AWB
Transportation| Verified traveller| Airline cargo service
Assignment| Traveller trip| Cargo shipment/AWB
Capacity| Traveller baggage| Cargo allocation
Tracking| D2F booking/trip| D2F parcel + AWB
Pricing| Category and direction| Air freight tariff
Operations| Traveller acceptance and handover| Cargo manifest and airline handling

7. Implementation Expectations

Rehan, the important point is that D2F Connect is a managed traveller-to-parcel matching platform, not a traditional cargo booking system.

The application should support the complete relationship between:

Customer → Parcel → Booking → Traveller Trip → Assignment → Payment → Handover → Delivery

Each booking should maintain its own tracking history, pricing information, and operational status.

A traveller trip may carry several customers' parcels, but each parcel must remain individually identifiable and traceable.

The admin dashboard must provide full visibility and control over trips, parcels, assignments, payments, traveller capacity, and delivery confirmations.

The system should be designed so that the separate Air Cargo AWB module can later share customer accounts and common infrastructure without mixing the two operational workflows.

Please use this business logic when reviewing the current MVP implementation and identifying what is already completed versus what still needs development.