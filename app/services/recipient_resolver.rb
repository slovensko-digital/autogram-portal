class RecipientResolver
  class << self
    def assign_identity(recipient)
      assign_portal_instance(recipient)

      if recipient.portal_instance.present? || recipient.portal_instance_uuid.present?
        recipient.federation_mode = "federated"
        return recipient
      end

      recipient.federation_mode = "local"
      return recipient if recipient.email.blank? || recipient.user.present?

      recipient.user = User.find_by(email: recipient.email)
      recipient
    end

    private

    def assign_portal_instance(recipient)
      return if recipient.portal_instance.present? || recipient.portal_instance_uuid.blank?

      recipient.portal_instance = PortalInstance.find_by(uuid: recipient.portal_instance_uuid)
    end
  end
end
