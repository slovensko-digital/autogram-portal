class BundlesController < ApplicationController
  before_action :set_public_bundle, only: [ :show, :iframe ]
  skip_before_action :verify_authenticity_token, only: [ :iframe ]

  before_action :allow_iframe, only: [ :iframe ]

  def index
    @bundles = current_user.bundles.includes(:contracts, :author).order(created_at: :desc)
  end

  def show
    @bundle.contracts.includes(:documents, :avm_sessions)
  end

  def iframe
    no_header
    no_footer
    no_flash
  end

  private

  def set_public_bundle
    @bundle = Bundle.find_by_uuid!(params[:id])
  end

  def bundle_params
    params.require(:bundle)
  end
end
