class Api::V1::BundlesController < ApiController
  before_action :set_bundle, only: [ :show, :status, :destroy ]

  def create
    @bundle = Bundle.new(bundle_params)
    if @bundle.save
      render status: :created
    else
      if @bundle.errors.details[:uuid]&.any? { |e| e[:error] == :taken }
        return render json: { error: "Bundle with the given ID already exists" }, status: :conflict
      end

      # contract_uuid_errors = @bundle.errors.details.select { |key, _| key.to_s.start_with?("contracts.") && key.to_s.end_with?(".uuid") }
      # if contract_uuid_errors.any? { |_, details| details.any? { |e| e[:error] == :taken } }
      #   return render json: { error: "One or more contracts have a duplicate ID" }, status: :conflict
      # end

      render json: { errors: @bundle.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
  end

  def status
    if @bundle.completed?
      redirect_to api_v1_bundle_path(@bundle)
    else
      response.headers["Retry-After"] = 10
      render json: nil, status: :ok
    end
  end

  def destroy
    @bundle.destroy
    head :no_content
  end

  private

  def set_bundle
    @bundle = @current_user.bundles.find_by(uuid: params[:id])
    render json: { error: "Bundle not found" }, status: :not_found unless @bundle
  end

  def bundle_params
    permitted_params = params.permit(
      :id,
      contracts: [
        :id,
        { allowedMethods: [] },
        { documents: [ :filename, :content, :contentType, :url, :hash,
            xdcParameters: [
              :autoLoadEform,
              :containerXmlns,
              :embedUsedSchemas,
              :fsFormIdentifier,
              :identifier,
              :schema,
              :schemaIdentifier,
              :schemaMimeType,
              :transformation,
              :transformationIdentifier,
              :transformationLanguage,
              :transformationMediaDestinationTypeDescription,
              :transformationTargetEnvironment
            ]
          ]
        },
        { signatureParameters: [ :level, :format, :container, :en319132, :addContentTimestamp ] }
      ],
      webhook: [ :url, :method ],
      postalAddress: [ :address, :recipientName ],
      recipients: [ :name, :email, :phone ]
    )

    attributes = {
      author: @current_user,
      contracts_attributes: permitted_params[:contracts]&.map do |contract|
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
        }.compact
      end || [],
      recipients_attributes: permitted_params[:recipients] || []
    }

    if permitted_params[:webhook].present?
      attributes[:webhook_attributes] = permitted_params[:webhook].transform_keys(&:underscore)
    end

    if permitted_params[:postalAddress].present?
      attributes[:postal_address_attributes] = permitted_params[:postalAddress].transform_keys(&:underscore)
    end

    if permitted_params[:id].present?
      attributes[:uuid] = permitted_params[:id]
    end

    attributes
  end
end
