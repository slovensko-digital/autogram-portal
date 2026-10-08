module SigningHelper
  SESSION_START_ROUTES = {
    "AutogramSession" => :autogram_contract_sessions_path,
    "AvmSession" => :avm_contract_sessions_path,
    "EidentitaSession" => :eidentita_contract_sessions_path,
    "PodpisujSession" => :podpisuj_contract_sessions_path,
    "AdesEvidenceSession" => :ades_contract_sessions_path
  }.freeze

  # Starts a new session in the signing app of the given one, e.g. to sign again after it failed.
  def restart_session_path(session, **params)
    route = SESSION_START_ROUTES[session.type]
    public_send(route, session.contract, **params) if route
  end

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
