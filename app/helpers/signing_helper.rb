module SigningHelper
  # The page a signer returns to from signing a contract: its bundle, or the contract itself
  # when the signer cannot open the bundle.
  def signing_page_path(contract, recipient: nil, **params)
    if contract.signed_through_bundle?(recipient: recipient)
      sign_bundle_path(contract.bundle, recipient: recipient&.uuid, **params)
    else
      sign_contract_path(contract, recipient: recipient&.uuid, **params)
    end
  end
end
