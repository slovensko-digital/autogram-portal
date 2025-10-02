class BundlesController < ApplicationController
  before_action :set_bundle, only: [ :show, :edit, :update, :destroy ]

  def index
    @bundles = Bundle.all
  end

  def show
  end

  def new
    @bundle = Bundle.new
    @bundle.author = current_user
  end

  def create
    @bundle = Bundle.new(bundle_params)
    if @bundle.save
      redirect_to @bundle, notice: "Bundle was successfully created."
    else
      render :new
    end
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

  private

  def set_bundle
    @bundle = Bundle.find(params[:id])
  end

  def bundle_params
    params.require(:bundle).permit(:name, :description)
  end
end
