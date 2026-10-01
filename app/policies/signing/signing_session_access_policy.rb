class Signing::SigningSessionAccessPolicy < ApplicationPolicy
  def create?
    web_context? && record.signer_contract&.contract == record.contract
  end

  def show?
    web_context? && bound_session?
  end

  def parameters?
    show? && (record.token_authorized || allowed_user?)
  end

  def download?
    parameters?
  end

  def upload?
    parameters?
  end

  def destroy?
    show? && allowed_user?
  end

  def request_verification?
    show? && record.session.signer_contract == record.signer_contract
  end

  def verify_verification?
    request_verification?
  end

  def complete_signing?
    request_verification?
  end

  def get_webhook?
    show?
  end

  def standard_webhook?
    show?
  end

  private

  def web_context?
    context.is_a?(AuthorizationContext::Web) && record.contract.present?
  end

  def bound_session?
    record.session.present? && record.session.signer_contract.contract == record.contract
  end

  def allowed_user?
    return false unless context.user
    return true if record.contract.managed_by?(context.tenant)

    signer = record.session.signer
    case signer
    when UserSigner
      signer.user == context.user
    when RecipientSigner
      recipient = signer.recipient
      return false if recipient&.withdrawn?

      recipient&.user == context.user || recipient&.email == context.user.email
    else
      false
    end
  end
end
