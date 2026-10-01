class SignatureEvidenceRecordPolicy < ApplicationPolicy
  def public_access?
    context.is_a?(AuthorizationContext::Web)
  end

  def download_private?
    context.is_a?(AuthorizationContext::Web) && record.private_evidence_accessible_by?(context.tenant)
  end
end
