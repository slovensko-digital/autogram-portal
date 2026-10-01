class Api::V1::DocumentPolicy < Api::V1::ApplicationPolicy
  def show?
    record.contract.present? && Api::V1::ContractPolicy.new(context, record.contract).show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      contracts = Api::V1::ContractPolicy::Scope.new(context, Contract.all).resolve
      scope.where(contract_id: contracts.select(:id))
    end
  end
end
