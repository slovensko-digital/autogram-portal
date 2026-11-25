class Signing::SigningBundleAccessPolicy < ApplicationPolicy
  def sign?
    return false unless web_context?
    return bound_recipient? if record.recipient.present?

    record.bundle.publicly_visible? || BundlePolicy.new(context, record.bundle).manage?
  end

  def autogram_batch?
    sign?
  end

  def accept?
    web_context? && bound_recipient?
  end

  def decline?
    accept?
  end

  # Signing on paper is only for the recipient the signing link belongs to, or the recipient of the
  # paper signature a phone link opens (PaperSignerResolution validates the PaperSignatureAccessToken).
  def paper_sign?
    web_context? && bound_recipient?
  end

  private

  def web_context?
    web? && record.bundle.present?
  end

  def bound_recipient?
    record.recipient.present? && record.recipient.bundle == record.bundle
  end
end
