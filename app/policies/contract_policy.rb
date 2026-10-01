class ContractPolicy < ApplicationPolicy
  def index?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant.present?
  end

  def manage?
    index? && record.managed_by?(context.tenant)
  end

  def create?
    public_access?
  end

  def public_access?
    context.is_a?(AuthorizationContext::Web)
  end

  def authenticate_for_actions?
    public_access? && (context.user.present? || record.anonymous?)
  end

  def show?
    public_access? && (record.anonymous? || manage?)
  end

  def update?
    show?
  end

  def destroy?
    show?
  end

  def request_signatures?
    manage?
  end

  def signature_extension?
    manage?
  end

  def extend_signatures?
    manage?
  end

  def content_versions?
    manage? && record.tenant.archivation_enabled?
  end

  def prepare_signature_fields?
    record.bundle.present? && BundlePolicy.new(context, record.bundle).manage?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant.present?

      scope.where(tenant: context.tenant)
    end
  end
end
