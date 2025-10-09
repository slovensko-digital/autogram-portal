class Api::V1::ContractsController < ApiController
  before_action :set_contract, only: [:show, :signed_document]

  def create
    contract = Contract.new(contract_params)
    if contract.save
      render json: { message: "Contract created successfully", contract: contract }, status: :created
    else
      render json: { errors: contract.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render partial: "api/v1/contracts/contract", locals: { contract: @contract }
  end

  def signed_document
    if @contract.signed_document.attached?
      render partial: "api/v1/contracts/signed_document", locals: { signed_document: @contract.signed_document }
    else
      render json: { error: "No signed document available" }, status: :not_found
    end
  end

  def status
    if @contract.awaiting_signature?
      response.headers["Retry-After"] = 10
      render json: nil, status: :ok
    else
      redirect_to api_v1_contract_path(@contract)
    end
  end

  private

  def set_contract
    @contract = Contract.find_by(uuid: params[:id])
    render json: { error: "Contract not found" }, status: :not_found unless @contract
  end
end
