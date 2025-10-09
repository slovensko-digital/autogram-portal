class BundlesController < ApplicationController
  before_action :set_bundle, only: [ :show, :edit, :update, :destroy, :iframe ]
  skip_before_action :verify_authenticity_token, only: [ :iframe ]

  before_action :allow_iframe, only: [ :iframe ]

  def index
    @bundles = Bundle.includes(:contracts, :author).order(created_at: :desc)
  end

  def show
    @bundle.contracts.includes(:documents, :avm_sessions)
  end

  def edit
  end

  def update
    if @bundle.update(bundle_params)
      redirect_to @bundle, notice: "Bundle was successfully updated."
    else
      render :edit
    end
  end

  def destroy
    @bundle.destroy
    redirect_to bundles_url, notice: "Bundle was successfully destroyed."
  end

  def iframe
    no_header
    no_footer
    no_flash
  end

  private

  def set_bundle
    @bundle = Bundle.find_by_uuid(params[:id])
  end

  def bundle_params
    params.require(:bundle)
  end
end
