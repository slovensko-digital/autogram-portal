class BundlesController < ApplicationController
  before_action :set_bundle, only: [ :show, :edit, :update, :destroy ]
  skip_before_action :verify_authenticity_token, only: [ :iframe ]

  before_action :allow_iframe, only: [ :iframe ]

  def index
    @bundles = current_user.bundles.includes(:contracts, :author).order(created_at: :desc)
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

  def iframe
    @bundle = Bundle.publicly_visible.find_by_uuid!(params[:id])

    no_header
    no_footer
    no_flash
  end

  def sign
    if params[:recipient]
      @recipient = Recipient.find_by_uuid!(params[:recipient])
      @bundle = @recipient.bundle
    else
      @bundle = Bundle.publicly_visible.find_by_uuid(params[:id]) || current_user&.bundles&.find_by_uuid(params[:id])
    end

    raise ActiveRecord::RecordNotFound unless @bundle
  end

  private

  def set_bundle
    @bundle = Bundle.find_by!(uuid: params[:id], author: current_user)
  end

  def bundle_params
    params.require(:bundle).except(:step).permit(
      :note,
      :publicly_visible,
      recipients_attributes: [ :id, :email, :_destroy ]
    )
  end
end
