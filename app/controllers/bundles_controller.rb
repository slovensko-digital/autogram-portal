class BundlesController < ApplicationController
  before_action :set_public_bundle, only: [ :iframe, :signatures, :sign ]
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
      redirect_to @bundle
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
end
