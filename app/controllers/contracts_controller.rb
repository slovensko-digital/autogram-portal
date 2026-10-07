class ContractsController < ApplicationController
  before_action :set_contract, except: [ :new, :index, :create ]
  # Anyone with the contract UUID may view and sign it.
  before_action :skip_authorization, only: [ :show_bundle, :actions, :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session, :signed_document, :validate ]
  before_action :claim_pending_anonymous_contract, only: [ :show, :actions ]
  before_action :authorize_contract!, only: [ :show, :update, :destroy ]
  before_action :set_recipient, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  before_action :render_sign_limit_reached_if_needed, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  before_action :set_signer_contract, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  before_action :allow_iframe, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  skip_before_action :ensure_tenant_selected, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ], if: -> { params[:iframe].present? }
  before_action :ensure_prepared_signature_field_appearance_completed, only: [ :sign, :signature_apps ]
  before_action :ensure_onboarding, only: [ :signature_apps, :physical_signing ]
  before_action :ensure_visual_signing_allowed, only: [ :visual_signing, :create_visual_session ]
  before_action :ensure_signature_field_appearance_assignment, only: [ :visual_signing, :create_visual_session ]

  rescue_from Pundit::NotAuthorizedError, with: :render_contract_denial

  helper_method :contract_back_path

  def index
    authorize Contract
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting completed])

    order_dir = @sort == "oldest" ? :asc : :desc
    contracts = policy_scope(Contract).standalone
    contracts = case @state
    when "awaiting"
      contracts.left_outer_joins(:content_versions).where(contract_content_versions: { id: nil })
    when "completed"
      contracts.joins(:content_versions).distinct
    else
      contracts
    end

    @contracts = contracts.includes(:documents).order(created_at: order_dir)
  end

  def new
    @contract = Contract.new
    authorize @contract
    @current_user = current_user
  end

  def create
    authorize Contract
    @contract = Contract.new(
      tenant: current_tenant,
      author: current_user,
      author_notifications_enabled: true,
      allowed_methods: Contract::OWN_SIGNING_DEFAULT_METHODS.dup,
      documents: [ Document.new(params.require(:document).permit(:blob)) ]
    )

    unless current_user
      unless params.dig(:contract, :agree_to_policies) == "1"
        @contract.errors.add(:agree_to_policies, t("contracts.alerts.missing_policy_agreement"))
        return render :new, locals: { errors: [ t("contracts.alerts.missing_policy_agreement") ] }, status: :unprocessable_entity
      end
    end

    @contract.save!

    redirect_to @contract

  rescue ActiveRecord::RecordInvalid
    render :new, locals: { errors: @contract.errors }, status: :unprocessable_entity
  end

  def show
  end

  def show_bundle
    head :not_found unless @contract.bundle
  end

  def content_versions
    authorize @contract

    @content_versions = @contract.signed_document_versions.with_attached_file
  end

  def actions
    render partial: "actions"
  end

  def authenticate_for_actions
    authorize @contract
    return redirect_to actions_contract_path(@contract) if current_user.present?

    session[:pending_contract_claim_uuid] = @contract.uuid
    store_location_for(:user, contract_path(@contract))
    redirect_to new_user_session_path
  end

  def signature_extension
    authorize @contract

    target_level = params[:target_level].presence&.upcase || "T"
    return head :unprocessable_entity unless @contract.extendable_signatures?(target_level: target_level)

    render partial: "signature_extension", locals: { target_level: target_level }
  end

  def signature_parameters
    if params[:target_step] == "request_signature"
      authorize @contract, :request_signatures?
    else
      skip_authorization
    end

    @next_step = params[:target_step]
    render partial: "signature_parameters"
  end

  def extend_signatures
    authorize @contract

    target_level = params[:target_level].presence&.upcase || "T"
    return_url = @contract.bundle ? show_bundle_contract_path(@contract) : contract_path(@contract)
    return redirect_to return_url, alert: t("documents.alerts.signatures_already_extended", target_level: target_level) unless @contract.extendable_signatures?(target_level: target_level)

    begin
      @contract.extend_signatures!(target_level: target_level)
      redirect_to return_url, notice: t("documents.alerts.signature_extended_successfully", target_level: target_level)
    rescue PlanLimits::Exceeded => e
      redirect_to return_url, alert: e.message
    rescue => e
      redirect_to return_url, alert: t("documents.alerts.failed_to_extend_signatures", error: e.message)
    end
  end

  def sign
  end

  def signature_apps
  end

  def physical_signing
  end

  def visual_signing
    @visual_stamp_purpose = visual_stamp_purpose
    @visual_stamp_document = visual_stamp_source_document(@visual_stamp_purpose)
    @assigned_signature_field_preparation = assigned_signature_field_preparation if @visual_stamp_purpose == "signature_field_appearance"
    @visual_stamp_locked = @assigned_signature_field_preparation.present?
    @visual_stamp = latest_visual_stamp_for(visual_stamp_record_document, @visual_stamp_purpose) if %w[qes_preparation signature_field_appearance].include?(@visual_stamp_purpose)
    @visual_stamp_custom_text = @visual_stamp&.custom_text.presence || current_user&.name.to_s
  end

  def create_physical_session
    physical_session = PhysicalSession.create!(
      signer_contract: @signer_contract,
      status: :pending
    )
    physical_session.submitted_date = params[:submitted_date]
    physical_session.save!

    redirect_to sign_contract_path(@contract, recipient: @recipient&.uuid)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to physical_signing_contract_path(@contract, recipient: @recipient&.uuid),
                alert: t("contracts.submit_failed", errors: e.record&.errors&.full_messages&.to_sentence.presence || e.message)
  end

  def create_visual_session
    purpose = visual_stamp_purpose
    source_document = visual_stamp_source_document(purpose)
    document = visual_stamp_record_document
    raise ActiveRecord::RecordInvalid unless source_document&.is_pdf? && document&.is_pdf?

    existing_stamp = latest_visual_stamp_for(document, purpose) if %w[qes_preparation signature_field_appearance].include?(purpose)
    stamp_attributes = visual_stamp_attributes(purpose).merge(purpose: purpose)
    visual_stamp = @signer_contract.visual_stamps.build(stamp_attributes.merge(document: document))
    attach_visual_stamp_image(visual_stamp, existing_stamp)
    raise ActiveRecord::RecordInvalid, visual_stamp unless visual_stamp.valid?

    if purpose == "signature_field_appearance"
      ActiveRecord::Base.transaction do
        replace_existing_visual_stamp!(document, purpose)
        visual_stamp.save!
      end

      return redirect_to signature_field_appearance_completion_path
    end

    stamped_content = AutogramEnvironment.autogram_service.stamp_pdf(source_document, stamp: visual_stamp_service_params(visual_stamp, existing_stamp))

    session = nil

    ActiveRecord::Base.transaction do
      replace_existing_visual_stamp!(document, purpose) if purpose == "qes_preparation"

      visual_stamp.save!
      visual_stamp.file.attach(
        io: StringIO.new(stamped_content),
        filename: visual_stamp_filename(document),
        content_type: "application/pdf"
      )

      if visual_stamp.visual_method?
        replace_visual_content_versions!

        session = @signer_contract.sessions.create!(
          type: "VisualSession",
          signing_started_at: Time.current
        )
        @contract.add_signed_content_version!(
          content: stamped_content,
          filename: visual_stamp_filename(document),
          content_type: "application/pdf",
          origin: "visual"
        )
      end
    end

    session&.signed!

    if visual_stamp.qes_preparation?
      return redirect_to signature_apps_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe])
    end

    redirect_to contract_session_path(@contract, session, recipient: @recipient&.uuid, iframe: params[:iframe], show_completed: true)
  rescue ActiveRecord::RecordInvalid => e
    flash[:visual_stamp_errors] = visual_stamp_error_messages(e)
    flash[:visual_stamp_invalid_fields] = visual_stamp_invalid_fields(e)
    redirect_to visual_signing_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe], purpose: purpose)
  rescue AutogramService::ServiceUnavailableError => e
    redirect_to visual_signing_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe], purpose: purpose),
                alert: e.message
  end

  def signed_document
    redirect_to rails_blob_url(@contract.signed_document, disposition: "attachment"), allow_other_host: true
  end

  def validate
    @validation_results = @contract.validation_results
    if @validation_results.blank?
      respond_to do |format|
        format.html do
          render "validate_error", locals: { errors: [ "No documents are available for validation." ] }
        end
        format.json do
          render json: { errors: [ "No documents are available for validation." ] }, status: :unprocessable_entity
        end
      end
      return
    end

    begin
      respond_to do |format|
        format.html do
          render "validate"
        end
        format.json do
          render json: @validation_results
        end
      end
    rescue => e
      respond_to do |format|
        format.html do
          render "validate_error", locals: { errors: [ e.message ] }
        end
        format.json do
          render json: { errors: [ e.message ] }, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    authorize @contract, :request_signatures? if params[:next_step] == "request_signature"

    if @contract.update(contract_params)
      @contract.save!
      if params[:next_step] == "request_signature"
        bundle = Bundle.create!(contracts: [ @contract ], tenant: @contract.tenant, author: current_user, author_notifications_enabled: true)
        redirect_to bundle
      elsif params[:next_step] == "sign"
        redirect_to sign_contract_path(@contract)
      else
        redirect_to @contract
      end
    else
      render :show, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :show, locals: { flash: @contract.errors }, status: :unprocessable_entity
  end

  def destroy
    return redirect_to @contract, alert: I18n.t("contracts.destroy.failure_bundle_attached") if @contract.bundle.present?

    if @contract.destroy
      if current_user
        redirect_to contracts_path, notice: I18n.t("contracts.destroy.success")
      else
        redirect_to new_contract_path, notice: I18n.t("contracts.destroy.success")
      end
    else
      redirect_to @contract, alert: I18n.t("contracts.destroy.failure", error: e.message)
    end
  end

  private

  # "Back" from the contract actions leads to the screen the contract belongs to, not to the
  # referrer: the actions are the first step on the contract page itself.
  def contract_back_path
    return new_contract_path unless policy(@contract).manage?

    @contract.bundle ? bundle_path(@contract.bundle) : contracts_path
  end

  def claim_pending_anonymous_contract
    return unless current_user.present?
    return unless session[:pending_contract_claim_uuid] == @contract.uuid

    session.delete(:pending_contract_claim_uuid)
    @contract.with_lock do
      @contract.reload
      next unless @contract.anonymous?

      @contract.tenant = current_tenant
      @contract.author = current_user
      next if @contract.save

      # The tenant has no room for it (plan limits): the contract stays anonymous.
      flash.now[:alert] = t("contracts.alerts.claim_failed", errors: @contract.errors.full_messages.to_sentence)
      @contract.reload
    end
  end

  def authorize_contract!
    authorize @contract
  end

  def render_contract_denial(error)
    if [ "show?", "update?", "destroy?" ].include?(error.query.to_s)
      return if redirect_for_other_tenant(error.record)

      redirect_to new_contract_path, alert: t("contracts.alerts.unauthorized_edit_attempt")
    else
      head :forbidden
    end
  end

  def set_contract
    @contract = Contract.includes(:bundle).find_by!(uuid: params[:id])
  end

  def set_recipient
    if params[:recipient].present?
      @recipient = @contract.recipients.active.find_by(uuid: params[:recipient])

      return if @recipient

      withdrawn_recipient = @contract.recipients.withdrawn.find_by(uuid: params[:recipient])
      if withdrawn_recipient&.bundle
        redirect_to sign_bundle_path(withdrawn_recipient.bundle, recipient: withdrawn_recipient.uuid)
        return
      end

      raise ActiveRecord::RecordNotFound
    elsif current_user
      @recipient = @contract.recipients.active.find_by(user: current_user) ||
                   @contract.recipients.active.find_by(email: current_user.email)

      if @recipient.nil? && @contract.bundle.present? && policy(@contract.bundle).manage?
        @recipient = Recipient.find_or_create_author_proxy_for!(bundle: @contract.bundle, user: current_user)
      end
    end
  end

  def render_sign_limit_reached_if_needed
    bundle = @contract.bundle
    return unless bundle&.signature_request_limit_reached_for?(@recipient)

    render "bundles/sign_limit_reached", locals: { bundle: bundle }, status: :forbidden
  end

  def set_signer_contract
    if @recipient
      recipient_signer = @recipient.recipient_signer || @recipient.create_recipient_signer!
      @signer_contract = recipient_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif current_user
      user_signer = UserSigner.find_or_create_by!(user: current_user)
      @signer_contract = user_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif @contract.anonymous?
      @signer_contract = @contract.signer_contracts
                                  .joins(:signer)
                                  .find_by(signers: { type: "AnonymousSigner" })
      unless @signer_contract
        @signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: @contract)
      end
    elsif @contract.bundle
      # The anonymous signer the signing sessions of a bundled contract use (Contracts::SessionsController).
      @signer_contract = @contract.signer_contracts.joins(:signer).find_by(signers: { type: "AnonymousSigner" })
    end

    if @signer_contract&.superseded? && @contract.bundle
      redirect_to sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid, iframe: params[:iframe]),
                  notice: t("bundles.sign.signature_no_longer_required")
      return
    end

    return unless @signer_contract&.signed?

    if @contract.signed_through_bundle?(recipient: @recipient)
      redirect_to sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid, iframe: params[:iframe])
    elsif @contract.bundle
      # Signed on the contract page of a bundle the signer cannot open: the contract page shows it signed.
      redirect_to sign_contract_path(@contract, iframe: params[:iframe]) unless action_name == "sign"
    else
      @signer_contract.update_column(:signed_at, nil)
    end
  end

  def ensure_onboarding
    return if params[:iframe] == "no_onboarding"

    case action_name
    when "signature_apps"
      @qscd = params[:qscd] || current_user&.qscd || cookies[:qscd]
      redirect_to contract_onboarding_path(@contract, method: "electronic", step: "qscd_check", recipient: @recipient&.uuid, iframe: params[:iframe]) if @qscd.blank? || User.legacy_eid_card?(@qscd)
    when "physical_signing"
      redirect_to contract_onboarding_path(@contract, method: "physical", step: "physical_signing", recipient: @recipient&.uuid, iframe: params[:iframe]) unless current_user&.onboarding_completed?("physical")
    end
  end

  def contract_params
    permitted = params.require(:contract).permit(
      :uuid,
      allowed_methods: [],
      documents_attributes: [ :id, :blob, :_destroy ],
      signature_parameters_attributes: [ :id, :add_content_timestamp, :level, :format, :container, :en319132 ]
    )

    return permitted unless params[:next_step] == "sign"

    signature_format = permitted.dig(:signature_parameters_attributes, :format) || @contract.signature_parameters&.format
    compatible_methods = @contract.available_signature_methods_for(next_step: params[:next_step], signature_format: signature_format)

    permitted[:allowed_methods] = if compatible_methods.one?
      compatible_methods
    else
      Array(permitted[:allowed_methods]) & compatible_methods
    end

    permitted
  end

  def visual_stamp_purpose
    params[:purpose].presence_in(%w[visual_method qes_preparation signature_field_appearance]) || "visual_method"
  end

  def default_visual_stamp_attributes
    if visual_stamp_purpose == "signature_field_appearance" && assigned_signature_field_preparation.present?
      return {
        page: assigned_signature_field_preparation.page,
        x: assigned_signature_field_preparation.x.to_f,
        y: assigned_signature_field_preparation.y.to_f,
        width: assigned_signature_field_preparation.width.to_f,
        height: assigned_signature_field_preparation.height.to_f
      }
    end

    {
      page: 1,
      x: 40,
      y: 40,
      width: VisualStamp::MAX_WIDTH,
      height: 52
    }
  end

  def visual_stamp_attributes(purpose)
    default_visual_stamp_attributes
      .merge(visual_stamp_params.except(:text, :custom_text, :content_mode, :image, :drawing_data).to_h.symbolize_keys)
      .merge(text: visual_stamp_text(purpose))
  end

  def visual_stamp_params
    params.fetch(:stamp, {}).permit(:page, :x, :y, :width, :height, :text, :custom_text, :content_mode, :image, :drawing_data)
  end

  def visual_stamp_text(purpose)
    custom_text = (visual_stamp_params[:custom_text].presence || visual_stamp_params[:text]).to_s.strip
    graphic_mode = %w[image draw].include?(visual_stamp_params[:content_mode])

    if purpose == "qes_preparation"
      return VisualStamp::QES_MANDATORY_TEXT if graphic_mode || custom_text.blank?

      [ VisualStamp::QES_MANDATORY_TEXT, custom_text ].join("\n")
    elsif graphic_mode
      nil
    else
      custom_text
    end
  end

  def attach_visual_stamp_image(visual_stamp, existing_stamp)
    case visual_stamp_params[:content_mode]
    when "image"
      image = visual_stamp_params[:image]
      if image.present?
        visual_stamp.image.attach(image)
      elsif existing_stamp&.image&.attached?
        visual_stamp.image.attach(existing_stamp.image.blob)
      end
    when "draw"
      content, mime_type = visual_stamp_drawing_payload
      if content.present? && mime_type.present?
        visual_stamp.image.attach(
          io: StringIO.new(content),
          filename: "signature-drawing.png",
          content_type: mime_type
        )
      elsif existing_stamp&.image&.attached?
        visual_stamp.image.attach(existing_stamp.image.blob)
      end
    end
  end

  def visual_stamp_drawing_payload
    drawing_data = visual_stamp_params[:drawing_data].to_s
    return [ nil, nil ] if drawing_data.blank?

    match = drawing_data.match(%r{\Adata:(image\/[a-zA-Z0-9.+-]+);base64,(.+)\z}m)
    return [ nil, nil ] unless match

    [ Base64.strict_decode64(match[2]), match[1] ]
  rescue ArgumentError
    [ nil, nil ]
  end

  def visual_stamp_service_params(visual_stamp, existing_stamp = nil)
    stamp = {
      page: visual_stamp.page,
      x: visual_stamp.x.to_f,
      y: visual_stamp.y.to_f,
      width: visual_stamp.width.to_f,
      height: visual_stamp.height.to_f,
      text: visual_stamp.text,
      altText: visual_stamp_alt_text(visual_stamp)
    }

    if visual_stamp.image.attached?
      image_content, image_mime_type = visual_stamp_image_payload(existing_stamp)
      stamp[:imageContent] = Base64.strict_encode64(image_content) if image_content
      stamp[:imageMimeType] = image_mime_type if image_mime_type
    end

    stamp
  end

  # Alternative text of the stamp in tagged PDFs, so assistive technologies announce the visual signature.
  def visual_stamp_alt_text(visual_stamp)
    date = Date.current.strftime(t("contracts.visual_stamp_alt_text.date_format"))
    name = @signer_contract.signer.recipient&.name.presence || @signer_contract.signer.user&.name.presence
    alt_text = name ? t("contracts.visual_stamp_alt_text.with_name", name: name, date: date) : t("contracts.visual_stamp_alt_text.without_name", date: date)
    text = visual_stamp.text.to_s.squish

    alt_text = "#{alt_text}. #{text}" if text.present? && text != name
    alt_text.truncate(500)
  end

  def visual_stamp_image_payload(existing_stamp)
    if visual_stamp_params[:content_mode] == "draw"
      return visual_stamp_drawing_payload
    end

    image = visual_stamp_params[:image]
    if image.present?
      image.rewind if image.respond_to?(:rewind)
      content = image.read
      image.rewind if image.respond_to?(:rewind)
      return [ content, image.content_type ]
    end

    return unless existing_stamp&.image&.attached?

    [ existing_stamp.image.download, existing_stamp.image.blob.content_type ]
  end

  def visual_stamp_source_document(purpose = visual_stamp_purpose)
    return visual_stamp_record_document if purpose == "qes_preparation"

    @contract.latest_source_content_version&.document || visual_stamp_record_document
  end

  def visual_stamp_record_document
    return assigned_signature_field_preparation.document if visual_stamp_purpose == "signature_field_appearance" && assigned_signature_field_preparation.present?

    @contract.documents.first
  end

  def latest_visual_stamp_for(document, purpose)
    return unless document && @signer_contract

    @signer_contract.visual_stamps.where(document: document, purpose: purpose).with_attached_image.order(created_at: :desc).first
  end

  def replace_existing_visual_stamp!(document, purpose)
    @signer_contract.visual_stamps.where(document: document, purpose: purpose).destroy_all
  end

  def replace_visual_content_versions!
    @contract.content_versions.where(origin: "visual").destroy_all
  end

  def visual_stamp_filename(document)
    "#{File.basename(document.filename, '.*').sub(/-visual\z/, '')}-visual.pdf"
  end

  def signed_document_param
    params.require(:signed_document)
  end

  def ensure_visual_signing_allowed
    return if visual_stamp_purpose == "signature_field_appearance"
    return if @contract.visual_signing_allowed?

    redirect_to visual_signing_unavailable_redirect_path, alert: t("contracts.alerts.visual_signing_not_available_for_signed_pades")
  end

  def ensure_prepared_signature_field_appearance_completed
    return unless @contract.prepared_signature_field_appearance_required_for?(recipient: @recipient, signer_contract: @signer_contract)

    if signature_apps_frame_request?
      render partial: "signature_field_appearance_required",
             locals: {
               frame_id: request.headers["Turbo-Frame"],
               contract: @contract,
               recipient: @recipient
             }
      return
    end

    redirect_to visual_signing_contract_path(
      @contract,
      recipient: @recipient&.uuid,
      iframe: params[:iframe],
      purpose: "signature_field_appearance"
    )
  end

  def ensure_signature_field_appearance_assignment
    return unless visual_stamp_purpose == "signature_field_appearance"
    return if assigned_signature_field_preparation.present?

    redirect_to visual_signing_unavailable_redirect_path,
                alert: t("contracts.alerts.signature_field_appearance_unavailable")
  end

  def assigned_signature_field_preparation
    return @assigned_signature_field_preparation if defined?(@assigned_signature_field_preparation)

    @assigned_signature_field_preparation = @contract.prepared_signature_field_preparation_for(recipient: @recipient)
  end

  def signature_apps_frame_request?
    action_name == "signature_apps" && request.headers["Turbo-Frame"].present?
  end

  def visual_stamp_error_messages(error)
    messages = error.record&.errors&.full_messages.presence
    messages || [ t("contracts.visual_signing.invalid_document") ]
  end

  # Form fields to mark as invalid on the visual signing page, in the order they appear there.
  def visual_stamp_invalid_fields(error)
    attributes = error.record&.errors&.attribute_names || []
    fields = attributes.map { |attribute| attribute == :base || attribute == :text ? :custom_text : attribute }
    (%i[x y width height custom_text image] & fields).map(&:to_s)
  end

  def visual_signing_unavailable_redirect_path
    helpers.signing_page_path(@contract, recipient: @recipient, iframe: params[:iframe])
  end

  def signature_field_appearance_completion_path
    if should_resume_ades_after_signature_field_appearance?
      ades_contract_sessions_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe])
    else
      signature_apps_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe])
    end
  end

  def should_resume_ades_after_signature_field_appearance?
    return true if params[:resume_signing_method] == "ades"

    params[:resume_signing_method].blank? && @contract.allowed_methods == [ "ades" ] && AdesEvidenceSession.available?(@contract, recipient: @recipient)
  end
end
