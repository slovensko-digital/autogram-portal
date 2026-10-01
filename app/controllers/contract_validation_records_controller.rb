class ContractValidationRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_archivation_enabled!
  before_action :set_contract_validation_record, only: [ :destroy, :refresh ]
  after_action :verify_policy_scoped

  rescue_from Pundit::NotAuthorizedError, with: :render_archivation_denial

  def index
    @sort = params[:sort].presence_in(%w[deadline newest oldest]) || "deadline"
    @state = params[:state].presence_in(%w[all expiring expired healthy unknown notexpired]) || "notexpired"

    records = policy_scope(ContractValidationRecord)
                .latest_per_contract
                .includes({ contract: :content_versions }, :contract_content_version)
    records = case @state
    when "expiring"
      records.expiring
    when "expired"
      records.expired
    when "healthy"
      records.healthy
    when "unknown"
      records.unknown
    when "notexpired"
      records.notexpired
    else
      records
    end

    @contract_validation_records = case @sort
    when "newest"
      records.order(updated_at: :desc)
    when "oldest"
      records.order(updated_at: :asc)
    else
      records.order(Arel.sql("CASE WHEN expires_at IS NULL THEN 1 ELSE 0 END ASC"), expires_at: :asc, updated_at: :desc)
    end
  end

  def destroy
    @contract_validation_record.destroy!

    redirect_to contract_validation_records_path, notice: t(".success")
  end

  def refresh
    unless @contract_validation_record.refreshable?
      return redirect_to contract_validation_records_path, alert: t(".not_refreshable")
    end

    ContractValidationRecordRefreshJob.perform_later(@contract_validation_record.id)
    redirect_to contract_validation_records_path, notice: t(".scheduled")
  end

  private

  def set_contract_validation_record
    @contract_validation_record = policy_scope(ContractValidationRecord).find(params[:id])
    authorize @contract_validation_record
  end

  def ensure_archivation_enabled!
    authorize ContractValidationRecord, :index?
  end

  def render_archivation_denial
    redirect_to root_path, alert: t("errors.archivation_disabled")
  end
end
