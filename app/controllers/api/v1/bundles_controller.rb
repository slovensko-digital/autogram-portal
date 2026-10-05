class Api::V1::BundlesController < ApiController
  before_action :set_bundle, only: [ :show, :status, :destroy ]
  after_action :verify_policy_scoped, except: [ :create ]

  def create
    authorize [ :api, :v1, Bundle ]
    @bundle = Bundle.new(bundle_params)
    @bundle.allow_blank_recipient_emails = true

    if @bundle.save
      render status: :created
    else
      if @bundle.errors.details[:uuid]&.any? { |e| e[:error] == :taken }
        return render json: { error: "Bundle with the given ID already exists" }, status: :conflict
      end

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
    if @bundle.destroy
      head :no_content
    else
      render json: { errors: @bundle.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_bundle
    @bundle = policy_scope([ :api, :v1, Bundle ]).find_by(uuid: params[:id])
    if @bundle
      authorize [ :api, :v1, @bundle ]
    else
      render json: { error: "Bundle not found" }, status: :not_found
    end
  end

  def bundle_params
    permitted_params = params.permit(
      :id,
      :name,
      :publiclyVisible,
      :signingRule,
      :requiredSignatures,
      :authorNotificationsEnabled,
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
      recipients: [ :name, :email, :locale, :uuid, :portalInstanceId, :mobilePhone, :phoneNumber ]
    )

    contracts = permitted_params[:contracts] || []
    contracts_documents = contracts.map { |contract| decode_documents(contract[:documents]) }
    ensure_documents_fit_limits!(contracts_documents)

    attributes = {
      tenant: current_tenant,
      contracts_attributes: contracts.zip(contracts_documents).map do |contract, documents|
        {
          uuid: contract[:id],
          allowed_methods: contract[:allowedMethods] || [],
          signature_parameters_attributes: contract[:signatureParameters]&.transform_keys(&:underscore) || {},
          documents_attributes: documents.map { |document| document_attributes(document) }
        }.compact
      end,
      recipients_attributes: permitted_params[:recipients]&.map do |recipient|
        recipient_attributes = recipient.to_h
        recipient_attributes["uuid"] ||= SecureRandom.uuid

        portal_instance_uuid = recipient_attributes.delete("portalInstanceId").presence
        recipient_attributes["portal_instance_uuid"] = portal_instance_uuid if portal_instance_uuid.present?

        mobile_phone = recipient_attributes.delete("mobilePhone").presence || recipient_attributes.delete("phoneNumber").presence
        recipient_attributes["mobile_phone"] = mobile_phone if mobile_phone.present?

        recipient_attributes
      end || []
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

    attributes[:publicly_visible] = permitted_params[:publiclyVisible] if permitted_params.key?(:publiclyVisible)
    attributes[:name] = permitted_params[:name] if permitted_params.key?(:name)
    attributes[:signing_rule] = permitted_params[:signingRule] if permitted_params[:signingRule].present?
    attributes[:required_signatures] = permitted_params[:requiredSignatures] if permitted_params[:requiredSignatures].present?
    attributes[:author_notifications_enabled] = permitted_params[:authorNotificationsEnabled] if permitted_params.key?(:authorNotificationsEnabled)

    attributes
  end
end
