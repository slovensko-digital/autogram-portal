# Each sign-in starts without a selected tenant, so users with several tenants
# choose one (see ApplicationController#ensure_tenant_selected).
Warden::Manager.after_set_user except: :fetch do |_user, auth, opts|
  auth.request.session.delete(:current_tenant_id) if opts[:scope] == :user
end
