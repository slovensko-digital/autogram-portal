class BundlesController < ApplicationController
  before_action :set_public_bundle, only: [ :iframe, :signatures, :sign ]
  before_action :set_bundle, only: [ :show, :edit, :update, :add_recipient, :notify_recipients ]
  skip_before_action :verify_authenticity_token, only: [ :iframe ]

  before_action :allow_iframe, only: [ :iframe ]

  def index
    @bundles = current_user.bundles.includes(:contracts, :author).order(created_at: :desc)
  end

  def show
    @bundle.contracts.includes(:documents, :avm_sessions)
  end

  def edit
  end

  def update
    if @bundle.update(bundle_params)
      redirect_to @bundle
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def add_recipient
    @recipient = @bundle.recipients.build(recipient_params)

    if @recipient.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "bundle_recipients_form",
            partial: "bundles/recipients_form",
            locals: { bundle: @bundle }
          )
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "bundle_recipients_form",
            partial: "bundles/recipients_form",
            locals: { bundle: @bundle, recipient_error: @recipient.errors.full_messages.join(", ") }
          )
        end
      end
    end
  end

  def notify_recipients
    @bundle.notify_recipients
    head :ok
  end

  def iframe
    no_header
    no_footer
    no_flash
  end

  def signatures
    render partial: "signatures"
  end

  private

  def set_public_bundle
    @bundle = Bundle.find_by_uuid!(params[:id])
  end

  def set_bundle
    @bundle = Bundle.find_by!(uuid: params[:id], author: current_user)
  end

  def bundle_params
    params.require(:bundle).permit(
      :note,
      recipients_attributes: [ :id, :email, :_destroy ]
    )
  end

  def recipient_params
    params.require(:recipient).permit(:email)
  end
end
