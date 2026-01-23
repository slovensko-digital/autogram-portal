class EidentitaService
  def initiate_signing(contract)
    document = contract.documents_to_sign.first
    return { error: "No document to sign" } unless document&.blob&.attached?

    {
      signing_started_at: Time.current
    }
  rescue StandardError => e
    { error: "Error initiating Eidentita signing: #{e.message}" }
  end
end
