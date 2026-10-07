class Api::V1::ContractsController < ApiController
  before_action :set_contract, only: [ :show, :signed_document, :status, :destroy ]
  after_action :verify_policy_scoped, except: [ :create ]

  def create
    authorize [ :api, :v1, Contract ]
    @contract = Contract.new(contract_params)
    @contract.tenant = current_tenant
    if @contract.save
      render status: :created
    else
      render json: { errors: @contract.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render partial: "api/v1/contracts/contract", locals: { contract: @contract }
  end

  def destroy
    if @contract.destroy
      render head :no_content
    else
      render json: { errors: @contract.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def signed_document
    if @contract.signed_document_attached?
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
      redirect_to @contract
    end
  end

  private

  def set_contract
    @contract = policy_scope([ :api, :v1, Contract ]).find_by(uuid: params[:id])
    if @contract
      authorize [ :api, :v1, @contract ]
    else
      render json: { error: "Contract not found" }, status: :not_found
    end
  end

  def contract_params
    contract = params.permit(
      :id,
      allowedMethods: [],
      signatureParameters: [ :container, :format, :level, :en319132, :addContentTimestamp ],
      documents: [ :filename, :content, :contentType, :url, :hash,
        xdcParameters: [ :autoLoadEform, :containerXmlns, :embedUsedSchemas, :fsFormIdentifier, :identifier, :schema, :schemaIdentifier, :schemaMimeType, :transformation, :transformationIdentifier, :transformationLanguage, :transformationMediaDestinationTypeDescription, :transformationTargetEnvironment ]
      ]
    )
    documents = decode_documents(contract[:documents])
    ensure_documents_fit_limits!([ documents ])

    {
      uuid: contract[:id],
      signing_required: true,
      allowed_methods: contract[:allowedMethods] || [],
      signature_parameters_attributes: contract[:signatureParameters]&.transform_keys(&:underscore) || {},
      documents_attributes: documents.map { |document| document_attributes(document) }
    }
  end
end
