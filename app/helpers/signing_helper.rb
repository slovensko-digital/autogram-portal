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

  # Embedded signing pages without the document preview would show nothing but the choice of a signing method,
  # so a single document that can be signed only electronically goes straight to the signing apps.
  # Links back to the signing page are hidden then, the page would only send the signer forward again.
  # A scan awaiting review keeps the signer on the signing page, which shows it; the signing apps would send them back.
  def signing_method_choice_skipped?(contract, recipient: nil)
    params[:iframe].in?(%w[no_preview no_onboarding]) &&
      (!contract.signed_through_bundle?(recipient: recipient) || contract.bundle.contracts.one?) &&
      contract.signing_methods_for(recipient: recipient, embedded: true) == [ "electronic" ] &&
      !recipient&.signer_contracts&.find_by(contract: contract)&.paper_scan_awaiting_review?
  end

  def electronic_signing_path(contract, recipient: nil)
    if contract.prepared_signature_field_appearance_required_for?(recipient: recipient)
      visual_signing_contract_path(contract, recipient: recipient&.uuid, iframe: params[:iframe], purpose: "signature_field_appearance")
    else
      qscd = params[:qscd].presence || current_user&.qscd || cookies[:qscd]
      signature_apps_contract_path(contract, recipient: recipient&.uuid, iframe: params[:iframe], qscd: qscd.presence)
    end
  end
end
