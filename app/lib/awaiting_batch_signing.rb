# Documents awaiting a user's signature across the bundles they received, split into those one Autogram batch
# signs (the signer confirms the whole batch once in the desktop app) and those to sign one by one.
class AwaitingBatchSigning
  Item = Data.define(:bundle, :recipient, :signer_contract) do
    def contract
      signer_contract.contract
    end
  end

  # +bundles+ are the received bundles awaiting the user's signature (Bundle.awaiting_signature_of).
  def initialize(bundles, user:)
    @bundles = bundles
    @user = user
  end

  # Documents signed in the batch, the oldest bundle first and within a bundle in upload order.
  def items
    pending_items.select { |item| item.contract.batch_signable? }
  end

  # Documents left out of the batch: they need another signing method or are a container of several files.
  def other_items
    pending_items.reject { |item| item.contract.batch_signable? }
  end

  # A batch pays off from two documents on.
  def available?
    items.many?
  end

  private

  def pending_items
    @pending_items ||= @bundles.includes(:tenant, contracts: :documents).order(:created_at).flat_map do |bundle|
      recipient = bundle.recipients.active.visible.find_by(user: @user)
      next [] if recipient.nil? || bundle.signature_request_limit_reached_for?(recipient)

      # The active recipient's own awaiting signature also means the contract awaits a signature.
      signer_contracts = recipient.signer_contracts.awaiting.index_by(&:contract_id)
      bundle.contracts.sort_by { |contract| [ contract.created_at, contract.id ] }.filter_map do |contract|
        signer_contract = signer_contracts[contract.id]
        next unless signer_contract

        signer_contract.contract = contract
        Item.new(bundle: bundle, recipient: recipient, signer_contract: signer_contract)
      end
    end
  end
end
