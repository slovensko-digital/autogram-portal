module AuthorizationContext
  Web = Data.define(:user, :tenant)
  TenantApi = Data.define(:tenant)
  Portal = Data.define(:portal_instance)
end
