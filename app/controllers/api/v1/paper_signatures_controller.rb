class Api::V1::PaperSignaturesController < ApiController
  before_action :set_contract
  after_action :verify_policy_scoped

  # The PDF scan of a submitted or approved paper signature of the token's tenant contract.
  def scan
    paper_signature = @contract.paper_signatures.where(status: %w[submitted approved]).find_by(uuid: params[:uuid])
    return render json: { error: "Paper signature not found" }, status: :not_found unless paper_signature&.scan&.attached?

    send_data paper_signature.scan.download, type: "application/pdf", disposition: "attachment", filename: paper_signature.scan.filename.to_s
  end

  private

  def set_contract
    @contract = policy_scope([ :api, :v1, Contract ]).find_by(uuid: params[:contract_id])
    if @contract
      authorize [ :api, :v1, @contract ], :show?
    else
      render json: { error: "Contract not found" }, status: :not_found
    end
  end
end
