class ContractsController < ApplicationController
  before_action :set_contract, except: [ :new, :index, :create ]
  before_action :verify_author, only: [ :show, :update, :destroy ]
  before_action :set_recipient, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  before_action :set_signer_contract, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  before_action :allow_iframe, only: [ :sign, :signature_apps, :physical_signing, :create_physical_session, :visual_signing, :create_visual_session ]
  before_action :ensure_onboarding, only: [ :signature_apps, :physical_signing ]

  def index
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting completed])

    order_dir = @sort == "oldest" ? :asc : :desc
    contracts = current_user.contracts.standalone
    contracts = case @state
    when "awaiting"
      contracts.left_outer_joins(:content_versions).where(contract_content_versions: { id: nil })
    when "completed"
      contracts.joins(:content_versions).distinct
    else
      contracts
    end

    @contracts = contracts.includes(:user, :documents).order(created_at: order_dir)
  end

  def new
    @contract = Contract.new
    @current_user = current_user
  end

  def create
    @contract = Contract.new(
      user: current_user,
      author_notifications_enabled: true,
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
    @previous_page = request.referrer
  end

  def show_bundle
    head :not_found unless @contract.bundle
  end

  def content_versions
    return head :forbidden unless author_of_contract? && current_user&.archivation_enabled?

    @content_versions = @contract.signed_document_versions.with_attached_file
  end

  def actions
    render partial: "actions", locals: { previous_page: params[:previous_page] }
  end

  def signature_extension
    return head :forbidden unless author_of_contract?

    target_level = params[:target_level].presence&.upcase || "T"
    return head :unprocessable_entity unless @contract.extendable_signatures?(target_level: target_level)

    render partial: "signature_extension", locals: { target_level: target_level }
  end

  def signature_parameters
    if params[:target_step] == "request_signature" && !author_of_contract?
      return head :forbidden
    end

    @next_step = params[:target_step]
    render partial: "signature_parameters"
  end

  def extend_signatures
    return head :forbidden unless author_of_contract?

    target_level = params[:target_level].presence&.upcase || "T"
    return_url = @contract.bundle ? show_bundle_contract_path(@contract) : contract_path(@contract)
    return redirect_to return_url, alert: t("documents.alerts.signatures_already_extended", target_level: target_level) unless @contract.extendable_signatures?(target_level: target_level)

    begin
      @contract.extend_signatures!(target_level: target_level)
      redirect_to return_url, notice: t("documents.alerts.signature_extended_successfully", target_level: target_level)
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
                alert: "Failed to submit: #{e.message}"
  end

  def create_visual_session
    documents = @contract.documents_to_sign
    document = documents.first
    raise ActiveRecord::RecordInvalid unless documents.one? && document&.is_pdf?

    purpose = visual_stamp_purpose
    stamp_attributes = visual_stamp_attributes.merge(purpose: purpose)
    visual_stamp = @signer_contract.visual_stamps.build(stamp_attributes.merge(document: document))
    raise ActiveRecord::RecordInvalid, visual_stamp unless visual_stamp.valid?

    stamped_content = AutogramEnvironment.autogram_service.stamp_pdf(document, stamp: visual_stamp_service_params(visual_stamp))

    visual_stamp.save!
    visual_stamp.file.attach(
      io: StringIO.new(stamped_content),
      filename: visual_stamp_filename(document),
      content_type: "application/pdf"
    )

    if visual_stamp.qes_preparation?
      return redirect_to signature_apps_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe])
    end

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
    session.signed!

    redirect_to sign_contract_path(@contract, recipient: @recipient&.uuid)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to visual_signing_contract_path(@contract, recipient: @recipient&.uuid),
                alert: "Failed to submit: #{e.message}"
  rescue AutogramService::ServiceUnavailableError => e
    redirect_to visual_signing_contract_path(@contract, recipient: @recipient&.uuid),
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
    if params[:next_step] == "request_signature" && !author_of_contract?
      return head :forbidden
    end

    if @contract.update(contract_params)
      @contract.save!
      if params[:next_step] == "request_signature"
        bundle = Bundle.create!(contracts: [ @contract ], author: current_user, author_notifications_enabled: true)
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

  def verify_author
    if @contract.user && @contract.user != current_user
      redirect_to new_contract_path, alert: t("contracts.alerts.unauthorized_edit_attempt")
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

      if @recipient.nil? && @contract.bundle.present? && current_user == @contract.bundle.author
        @recipient = Recipient.find_or_create_author_proxy_for!(bundle: @contract.bundle, user: current_user)
      end
    end
  end

  def set_signer_contract
    if @recipient
      recipient_signer = @recipient.recipient_signer || @recipient.create_recipient_signer!
      @signer_contract = recipient_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif current_user
      user_signer = UserSigner.find_or_create_by!(user: current_user)
      @signer_contract = user_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif @contract.user.nil?
      @signer_contract = @contract.signer_contracts
                                  .joins(:signer)
                                  .find_by(signers: { type: "AnonymousSigner" })
      unless @signer_contract
        @signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: @contract)
      end
    end

    return unless @signer_contract&.signed?

    if @contract.bundle
      redirect_to sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid)
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
    params.require(:contract).permit(
      :uuid,
      allowed_methods: [],
      documents_attributes: [ :id, :blob, :_destroy ],
      signature_parameters_attributes: [ :id, :add_content_timestamp, :level, :format, :container, :en319132 ]
    )
  end

  def visual_stamp_purpose
    params[:purpose].presence_in(%w[visual_method qes_preparation]) || "visual_method"
  end

  def default_visual_stamp_attributes
    {
      page: 1,
      x: 40,
      y: 40,
      width: 260,
      height: 52,
      text: VisualStamp::DEFAULT_TEXT
    }
  end

  def visual_stamp_attributes
    default_visual_stamp_attributes.merge(visual_stamp_params.to_h.symbolize_keys)
  end

  def visual_stamp_params
    params.fetch(:stamp, {}).permit(:page, :x, :y, :width, :height, :text)
  end

  def visual_stamp_service_params(visual_stamp)
    {
      page: visual_stamp.page,
      x: visual_stamp.x.to_f,
      y: visual_stamp.y.to_f,
      width: visual_stamp.width.to_f,
      height: visual_stamp.height.to_f,
      text: visual_stamp.text
    }
  end

  def visual_stamp_filename(document)
    "#{File.basename(document.filename, '.*')}-visual.pdf"
  end

  def signed_document_param
    params.require(:signed_document)
  end

  def author_of_contract?
    if @contract.bundle
      return current_user.present? && @contract.bundle.author == current_user
    end

    current_user.present? && @contract.user == current_user
  end
end
