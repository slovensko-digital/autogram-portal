module AuthorizationContext
  Web = Data.define(:user, :tenant)
  PendingTenantSelection = Data.define(:user)
  TenantApi = Data.define(:tenant)
  Portal = Data.define(:portal_instance)
end
