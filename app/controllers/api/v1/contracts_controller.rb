class Api::V1::ContractsController < ApiController
  before_action :set_contract, only: [ :show, :signed_document, :status, :destroy ]

  def create
    contract = Contract.new(contract_params)
    contract.user = current_user
    if contract.save
      render json: { message: "Contract created successfully", contract: contract }, status: :created
    else
      render json: { errors: contract.errors.full_messages }, status: :unprocessable_entity
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
      redirect_to @contract
    end
  end

  private

  def set_contract
    @contract = accessible_contracts.find_by(uuid: params[:id])
    render json: { error: "Contract not found" }, status: :not_found unless @contract
  end

  def accessible_contracts
    Contract
      .left_outer_joins(:bundle)
      .where("contracts.user_id = :user_id OR bundles.user_id = :user_id", user_id: current_user.id)
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
    {
      uuid: contract[:id],
      allowed_methods: contract[:allowedMethods] || [],
      signature_parameters_attributes: contract[:signatureParameters]&.transform_keys(&:underscore) || {},
      documents_attributes: contract[:documents]&.filter_map do |document|
        doc_attributes = {
          xdc_parameters_attributes: document[:xdcParameters]&.transform_keys(&:underscore) || {}
        }

        doc_attributes[:url] = document[:url] if document[:url].present?
        doc_attributes[:remote_hash] = document[:hash] if document[:hash].present?
        doc_attributes[:uuid] = document[:id] if document[:id].present?

        content = document[:content]
        if content.present?
          content = Base64.decode64(content) if document[:contentType].include?("base64")
          doc_attributes[:blob] = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(content),
            filename: document[:filename],
            content_type: document[:contentType].split(";").first.strip
          )
        end

        doc_attributes
      end || []
    }
  end
end
