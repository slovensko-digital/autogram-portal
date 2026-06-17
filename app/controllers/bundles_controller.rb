class BundlesController < ApplicationController
  MOBILE_DEVICE_USER_AGENT = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  helper_method :mobile_device_request?

  before_action :set_bundle, only: [ :show, :edit, :update, :destroy ]
  skip_before_action :verify_authenticity_token, only: [ :sign ], if: -> { params[:iframe].present? }
  before_action :allow_iframe, only: [ :sign, :autogram_batch ], if: -> { params[:iframe].present? }
  before_action :load_signing_bundle_context, only: [ :sign, :autogram_batch ]
  before_action :render_sign_withdrawn_if_needed, only: [ :sign, :autogram_batch ]
  before_action :set_batch_autogram_contracts, only: [ :sign, :autogram_batch ]
  before_action :ensure_batch_autogram_available!, only: [ :autogram_batch ]

  def index
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting completed declined no_recipients])

    order_dir = @sort == "oldest" ? :asc : :desc
    bundles = current_user.bundles

    awaiting_scope = current_user.bundles
                                 .joins(recipients: { recipient_signer: :signer_contracts })
                                 .merge(Recipient.active.visible)
                                 .where(signer_contracts: { signed_at: nil, declined_at: nil, superseded_at: nil })
                                 .distinct

    declined_scope = current_user.bundles
                                 .joins(recipients: { recipient_signer: :signer_contracts })
                                 .merge(Recipient.active.visible)
                                 .where.not(signer_contracts: { declined_at: nil })
                                 .distinct

    bundles = case @state
    when "awaiting"
      bundles.joins(:recipients)
             .merge(Recipient.active.visible)
             .where(id: awaiting_scope.select(:id))
             .where.not(id: declined_scope.select(:id))
             .distinct
    when "completed"
      bundles.joins(:recipients)
             .merge(Recipient.active.visible)
             .where.not(id: awaiting_scope.select(:id))
             .where.not(id: declined_scope.select(:id))
             .distinct
    when "declined"
      bundles.where(id: declined_scope.select(:id))
    when "no_recipients"
      bundles.where.not(id: bundles.joins(:recipients).merge(Recipient.active.visible).select(:id))
    else
      bundles
    end

    @bundles = bundles.includes(:contracts, :author, :recipients).order(created_at: order_dir)
  end

  def received
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting signed declined superseded])

    order_dir = @sort == "oldest" ? :asc : :desc
    recipient_bundles = Bundle.recipient_user(current_user).distinct

    awaiting_for_user_scope = Bundle.recipient_user(current_user)
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                                    .where(recipients: { user_id: current_user.id, withdrawn_at: nil, author_proxy: false })
                                    .where(signer_contracts: { signed_at: nil, declined_at: nil, superseded_at: nil })
                                    .distinct

    declined_for_user_scope = Bundle.recipient_user(current_user)
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                                    .where(recipients: { user_id: current_user.id, withdrawn_at: nil, author_proxy: false })
                                    .where.not(signer_contracts: { declined_at: nil })
                                    .distinct

    superseded_for_user_scope = Bundle.recipient_user(current_user)
                                      .joins(recipients: { recipient_signer: :signer_contracts })
                                      .where(recipients: { user_id: current_user.id, withdrawn_at: nil, author_proxy: false })
                                      .where.not(signer_contracts: { superseded_at: nil })
                                      .where(signer_contracts: { signed_at: nil })
                                      .where(signer_contracts: { declined_at: nil })
                                      .distinct

    @bundles = case @state
    when "awaiting"
      recipient_bundles.where(id: awaiting_for_user_scope.select(:id))
                       .where.not(id: declined_for_user_scope.select(:id))
    when "signed"
      recipient_bundles.where.not(id: awaiting_for_user_scope.select(:id))
                       .where.not(id: declined_for_user_scope.select(:id))
                       .where.not(id: superseded_for_user_scope.select(:id))
    when "declined"
      recipient_bundles.where(id: declined_for_user_scope.select(:id))
    when "superseded"
      recipient_bundles.where(id: superseded_for_user_scope.select(:id))
                       .where.not(id: awaiting_for_user_scope.select(:id))
    else
      recipient_bundles
    end

    @bundles = @bundles.includes(:contracts, :author).order(created_at: order_dir)

    @recipients_by_bundle = Recipient.active.visible.where(user: current_user, bundle_id: @bundles.map(&:id))
                                     .index_by(&:bundle_id)
  end

  def show
  end

  def edit
  end

  def update
    if @bundle.update(bundle_params)
      case params[:bundle][:step]
      when "note"
        render partial: "note_form"
      when "public_link"
        render partial: "public_link_form"
      when "signing_rule"
        render "recipients/index"
      else
        redirect_to @bundle
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @bundle.destroy
      redirect_to bundles_path, notice: I18n.t("bundles.destroy.success")
    else
      redirect_to @bundle, alert: I18n.t("bundles.destroy.failure")
    end
  end

  def sign
  end

  def autogram_batch
    @batch_items = @batch_autogram_contracts.map do |contract|
      session = find_or_create_batch_autogram_session(contract)
      session_token = SessionAccessToken.generate(contract: contract, session: session)

      {
        contract_id: contract.uuid,
        contract_name: contract.display_name.to_s,
        parameters_path: parameters_contract_session_path(contract, session, session_token: session_token),
        upload_path: upload_contract_session_path(contract, session, session_token: session_token)
      }
    end

    @return_path = sign_bundle_path(@bundle, recipient: @recipient&.uuid, iframe: params[:iframe])
  end

  def decline
    bundle = Bundle.find_by_uuid!(params[:id])
    recipient = recipient_for_bundle_action(bundle)

    if recipient.withdrawn?
      return redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                         alert: I18n.t("bundles.sign.signature_request_withdrawn")
    end

    if bundle.completed?
      return redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                         notice: I18n.t("bundles.sign.bundle_already_completed")
    end

    if recipient.superseded?
      return redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                         notice: I18n.t("bundles.sign.signature_no_longer_required")
    end

    affected_signer_contracts = recipient.signer_contracts
                                       .joins(:contract)
                                       .where(contracts: { bundle_id: bundle.id }, signed_at: nil, declined_at: nil, superseded_at: nil)
    affected_signer_contract_ids = affected_signer_contracts.pluck(:id)

    now = Time.current
    SignerContract.where(id: affected_signer_contract_ids).update_all(declined_at: now, updated_at: now)

    SignerContract.where(id: affected_signer_contract_ids).includes(:contract).find_each do |signer_contract|
      bundle.webhook&.fire_recipient_declined(recipient, signer_contract.contract)
    end

    redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                notice: I18n.t("bundles.sign.declined_notice")
  end

  def accept
    bundle = Bundle.find_by_uuid!(params[:id])
    recipient = recipient_for_bundle_action(bundle)

    if recipient.withdrawn?
      return redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                         alert: I18n.t("bundles.sign.signature_request_withdrawn")
    end

    if bundle.completed?
      return redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                         notice: I18n.t("bundles.sign.bundle_already_completed")
    end

    affected_signer_contracts = recipient.signer_contracts
                                       .joins(:contract)
                                       .where(contracts: { bundle_id: bundle.id }, signed_at: nil)
                                       .where.not(declined_at: nil)
    affected_signer_contract_ids = affected_signer_contracts.pluck(:id)

    now = Time.current
    SignerContract.where(id: affected_signer_contract_ids).update_all(declined_at: nil, updated_at: now)

    SignerContract.where(id: affected_signer_contract_ids).includes(:contract).find_each do |signer_contract|
      bundle.webhook&.fire_recipient_undeclined(recipient, signer_contract.contract)
    end

    redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                notice: I18n.t("bundles.sign.accepted_notice")
  end

  private

  def set_bundle
    @bundle = Bundle.find_by!(uuid: params[:id], author: current_user)
  end

  def bundle_params
    params.require(:bundle).except(:step).permit(
      :note,
      :publicly_visible,
      :signing_rule,
      :required_signatures,
      :author_notifications_enabled,
      recipients_attributes: [ :id, :email, :_destroy ]
    )
  end

  def recipient_for_bundle_action(bundle)
    if params[:recipient]
      bundle.recipients.find_by_uuid!(params[:recipient])
    else
      bundle.recipients.active.find_by!(user: current_user)
    end
  end

  def load_signing_bundle_context
    if params[:recipient]
      @recipient = Recipient.find_by_uuid!(params[:recipient])
      raise ActiveRecord::RecordNotFound unless @recipient.bundle.uuid == params[:id]
      @bundle = @recipient.bundle
      return
    end

    if current_user
      @bundle = Bundle.joins(:recipients)
                      .merge(Recipient.active.visible)
                      .where(recipients: { user: current_user }, uuid: params[:id]).first
      @recipient = @bundle&.recipients&.active&.find_by(user: current_user) if @bundle
    end

    @bundle ||= Bundle.publicly_visible.find_by_uuid(params[:id]) || current_user&.bundles&.find_by_uuid(params[:id])

    if current_user && @bundle && current_user == @bundle.author && @recipient.nil?
      @recipient = Recipient.find_or_create_author_proxy_for!(bundle: @bundle, user: current_user)
    end

    raise ActiveRecord::RecordNotFound unless @bundle
  end

  def render_sign_withdrawn_if_needed
    return unless @recipient&.withdrawn?

    render :sign_withdrawn, status: :gone
  end

  def set_batch_autogram_contracts
    @pending_batch_contracts = @bundle.contracts.select do |contract|
      next false unless contract.awaiting_signature?

      if @recipient
        @recipient.pending_contract?(contract)
      else
        public_signing_available?
      end
    end

    @batch_autogram_contracts = @pending_batch_contracts.select { |contract| contract.allowed_methods.include?("qes") }
    @batch_autogram_available = !mobile_device_request? && @pending_batch_contracts.many? && @batch_autogram_contracts.size == @pending_batch_contracts.size
  end

  def ensure_batch_autogram_available!
    return if @batch_autogram_available

    alert_key = mobile_device_request? ? "bundles.autogram_batch.desktop_only" : "bundles.sign.batch_sign_unavailable"

    redirect_to sign_bundle_path(@bundle, recipient: @recipient&.uuid, iframe: params[:iframe]),
                alert: I18n.t(alert_key)
  end

  def find_or_create_batch_autogram_session(contract)
    signer_contract = signer_contract_for_batch(contract)
    existing = signer_contract.sessions.pending.where(type: "AutogramSession").first
    return persist_batch_session_view_options(existing) if existing

    persist_batch_session_view_options(
      signer_contract.sessions.create!(
        type: "AutogramSession",
        signing_started_at: Time.current,
        options: batch_session_view_options
      )
    )
  end

  def persist_batch_session_view_options(session)
    return session if batch_session_view_options.empty?

    merged_options = (session.options || {}).merge(batch_session_view_options)
    session.update!(options: merged_options) if session.options != merged_options
    session
  end

  def batch_session_view_options
    {}.tap do |options|
      options["iframe"] = params[:iframe] if params[:iframe].present?
    end
  end

  def signer_contract_for_batch(contract)
    if @recipient
      recipient_signer = @recipient.recipient_signer || @recipient.create_recipient_signer!
      return recipient_signer.signer_contracts.find_or_create_by!(contract: contract)
    end

    if current_user
      user_signer = UserSigner.find_or_create_by!(user: current_user)
      return user_signer.signer_contracts.find_or_create_by!(contract: contract)
    end

    signer_contract = contract.signer_contracts
                             .joins(:signer)
                             .find_by(signers: { type: "AnonymousSigner" })
    return signer_contract if signer_contract

    AnonymousSigner.create!.signer_contracts.create!(contract: contract)
  end

  def public_signing_available?
    @bundle.publicly_visible? && @bundle.visible_recipients.none?
  end

  def mobile_device_request?
    request.user_agent.to_s.match?(MOBILE_DEVICE_USER_AGENT)
  end
end
