class ContractPolicy < ApplicationPolicy
  def index?
    in_tenant?
  end

  def manage?
    in_tenant? && record.managed_by?(context.tenant)
  end

  # Anyone may upload, including anonymous visitors.
  def create?
    web?
  end

  def authenticate_for_actions?
    web? && (context.user.present? || record.anonymous?)
  end

  def show?
    web? && (record.anonymous? || manage?)
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

  class Scope < TenantScope
  end
end
