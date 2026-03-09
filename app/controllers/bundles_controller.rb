class BundlesController < ApplicationController
  before_action :set_bundle, only: [ :show, :edit, :update, :destroy ]
  skip_before_action :verify_authenticity_token, only: [ :sign ], if: -> { params[:iframe].present? }
  before_action :allow_iframe, only: [ :sign ], if: -> { params[:iframe].present? }

  def index
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting completed declined])

    order_dir = @sort == "oldest" ? :asc : :desc
    bundles = current_user.bundles.includes(:contracts, :author, :recipients).order(created_at: order_dir)

    @bundles = bundles.to_a
    @bundles.select! { |b| !b.completed? && !b.recipients.any?(&:declined?) } if @state == "awaiting"
    @bundles.select! { |b| b.completed? } if @state == "completed"
    @bundles.select! { |b| b.recipients.any?(&:declined?) } if @state == "declined"
  end

  def received
    @sort = params[:sort].presence_in(%w[newest oldest]) || "newest"
    @state = params[:state].presence_in(%w[awaiting signed])

    order_dir = @sort == "oldest" ? :asc : :desc
    @bundles = Bundle.joins(:recipients)
                     .where(recipients: { user: current_user })
                     .includes(:contracts, :author)
                     .order(created_at: order_dir)
                     .distinct
                     .to_a

    @recipients_by_bundle = Recipient.where(user: current_user, bundle_id: @bundles.map(&:id))
                                     .index_by(&:bundle_id)

    if @state == "awaiting"
      @bundles.select! do |bundle|
        recipient = @recipients_by_bundle[bundle.id]
        recipient.present? && recipient.unsigned_contracts.any?
      end
    elsif @state == "signed"
      @bundles.select! do |bundle|
        recipient = @recipients_by_bundle[bundle.id]
        recipient.nil? || recipient.unsigned_contracts.none?
      end
    end
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
    recipient = if params[:recipient]
                  bundle.recipients.find_by_uuid!(params[:recipient])
                else
                  bundle.recipients.find_by!(user: current_user)
                end
    recipient.declined!
    redirect_to sign_bundle_path(bundle, recipient: recipient.uuid),
                notice: I18n.t("bundles.sign.declined_notice")
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
end
