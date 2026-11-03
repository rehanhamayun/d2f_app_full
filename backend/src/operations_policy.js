// Temporary rollout switches. Sign-in, organization boundaries, operational
// roles and physical custody evidence are always required. Set either flag to
// true to restore its original approval gate without changing client builds.
export const warehouseFacilityAuthorizationRequired = () =>
  process.env.WAREHOUSE_FACILITY_AUTHORIZATION_REQUIRED === 'true';
export const connectReceivingApprovalRequired = () =>
  process.env.CONNECT_RECEIVING_APPROVAL_REQUIRED === 'true';
