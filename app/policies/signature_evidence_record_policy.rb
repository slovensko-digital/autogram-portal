class SignatureEvidenceRecordPolicy < ApplicationPolicy
  def download_private?
    web? && record.private_evidence_accessible_by?(context.tenant)
  end
end
