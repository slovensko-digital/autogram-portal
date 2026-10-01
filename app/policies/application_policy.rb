class ApplicationPolicy
  # Principal checks shared by policies and scopes. Each controller base builds
  # one kind of context, so these also keep a policy from accepting another kind.
  module Principal
    private

    def web?
      context.is_a?(AuthorizationContext::Web)
    end

    def signed_in?
      web? && context.user.present?
    end

    # A signed-in user working in their selected tenant.
    def in_tenant?
      signed_in? && context.tenant.present?
    end

    def tenant_api?
      context.is_a?(AuthorizationContext::TenantApi) && context.tenant.present?
    end

    def portal?
      context.is_a?(AuthorizationContext::Portal) && context.portal_instance.present?
    end
  end

  include Principal

  attr_reader :context, :record

  def initialize(context, record)
    @context = context
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    include Principal

    attr_reader :context, :scope

    def initialize(context, scope)
      @context = context
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "Define a policy scope for #{self.class}"
    end
  end

  # Records of the tenant the signed-in user works in.
  class TenantScope < Scope
    def resolve
      in_tenant? ? scope.where(tenant: context.tenant) : scope.none
    end
  end
end
