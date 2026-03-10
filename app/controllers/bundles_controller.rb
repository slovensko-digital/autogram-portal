class BundlesController < ApplicationController
  before_action :set_bundle, only: [ :show, :edit, :update, :destroy ]
  skip_before_action :verify_authenticity_token, only: [ :sign ], if: -> { params[:iframe].present? }
  before_action :allow_iframe, only: [ :sign ], if: -> { params[:iframe].present? }

  def index
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting completed declined no_recipients])

    order_dir = @sort == "oldest" ? :asc : :desc
    bundles = current_user.bundles

    awaiting_scope = current_user.bundles
                                 .joins(recipients: { recipient_signer: :signer_contracts })
                                 .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                 .distinct

    declined_scope = current_user.bundles
                                 .joins(recipients: { recipient_signer: :signer_contracts })
                                 .where.not(signer_contracts: { declined_at: nil })
                                 .distinct

    bundles = case @state
    when "awaiting"
      bundles.joins(:recipients)
             .where(id: awaiting_scope.select(:id))
             .where.not(id: declined_scope.select(:id))
             .distinct
    when "completed"
      bundles.joins(:recipients)
             .where.not(id: awaiting_scope.select(:id))
             .where.not(id: declined_scope.select(:id))
             .distinct
    when "declined"
      bundles.where(id: declined_scope.select(:id))
    when "no_recipients"
      bundles.left_outer_joins(:recipients).where(recipients: { id: nil })
    else
      bundles
    end

    @bundles = bundles.includes(:contracts, :author, :recipients).order(created_at: order_dir)
  end

  def received
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting signed declined])

    order_dir = @sort == "oldest" ? :asc : :desc
    recipient_bundles = Bundle.recipient_user(current_user).distinct

    awaiting_for_user_scope = Bundle.recipient_user(current_user)
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                                    .where(recipients: { user_id: current_user.id })
                                    .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                    .distinct

    declined_for_user_scope = Bundle.recipient_user(current_user)
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                                    .where(recipients: { user_id: current_user.id })
                                    .where.not(signer_contracts: { declined_at: nil })
                                    .distinct

    @bundles = case @state
    when "awaiting"
      recipient_bundles.where(id: awaiting_for_user_scope.select(:id))
                       .where.not(id: declined_for_user_scope.select(:id))
    when "signed"
      recipient_bundles.where.not(id: awaiting_for_user_scope.select(:id))
                       .where.not(id: declined_for_user_scope.select(:id))
    when "declined"
      recipient_bundles.where(id: declined_for_user_scope.select(:id))
    else
      recipient_bundles
    end

    @bundles = @bundles.includes(:contracts, :author).order(created_at: order_dir)

    @recipients_by_bundle = Recipient.where(user: current_user, bundle_id: @bundles.map(&:id))
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
    if params[:recipient]
      @recipient = Recipient.find_by_uuid!(params[:recipient])
      @bundle = @recipient.bundle
    end

    if current_user
      @bundle ||= Bundle.joins(:recipients).where(recipients: { user: current_user }, uuid: params[:id]).first
      @recipient ||= @bundle.recipients.find_by(user: current_user) if @bundle
    end

    @bundle ||= Bundle.publicly_visible.find_by_uuid(params[:id]) || current_user&.bundles&.find_by_uuid(params[:id])

    raise ActiveRecord::RecordNotFound unless @bundle
  end

  def decline
    bundle = Bundle.find_by_uuid!(params[:id])
    recipient = recipient_for_bundle_action(bundle)
    affected_signer_contracts = recipient.signer_contracts
                                       .joins(:contract)
                                       .where(contracts: { bundle_id: bundle.id }, signed_at: nil, declined_at: nil)
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

  def set_bundle_for_sign
    if params[:recipient]
      @recipient = Recipient.find_by_uuid!(params[:recipient])
      @bundle = @recipient.bundle
    elsif current_user
      @bundle = Bundle.joins(:recipients).where(recipients: { user: current_user }, uuid: params[:id]).first
      @recipient = @bundle&.recipients&.find_by(user: current_user)
    end
  end

  def bundle_params
    params.require(:bundle).except(:step).permit(
      :note,
      :publicly_visible,
      recipients_attributes: [ :id, :email, :_destroy ]
    )
  end

  def recipient_for_bundle_action(bundle)
    if params[:recipient]
      bundle.recipients.find_by_uuid!(params[:recipient])
    else
      bundle.recipients.find_by!(user: current_user)
    end
  end
end
