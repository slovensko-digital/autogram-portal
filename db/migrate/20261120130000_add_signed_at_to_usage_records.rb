# When a document sent for signature was first signed by someone else than its author. Kept on the usage
# record, so it outlives the document and shows how many of the documents sent get signed.
class AddSignedAtToUsageRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :usage_records, :signed_at, :datetime

    reversible do |direction|
      direction.up { backfill }
    end
  end

  private

  def backfill
    execute <<~SQL
      UPDATE usage_records
      SET signed_at = signatures.signed_at
      FROM (
        SELECT signer_contracts.contract_id, min(signer_contracts.signed_at) AS signed_at
        FROM signer_contracts
        JOIN contracts ON contracts.id = signer_contracts.contract_id
        JOIN signers ON signers.id = signer_contracts.signer_id
        LEFT JOIN recipients ON recipients.id = signers.recipient_id
        WHERE signer_contracts.signed_at IS NOT NULL
          AND (contracts.author_id IS NULL OR coalesce(signers.user_id, recipients.user_id) IS DISTINCT FROM contracts.author_id)
        GROUP BY signer_contracts.contract_id
      ) signatures
      WHERE usage_records.kind = 'signature_request' AND usage_records.contract_id = signatures.contract_id
    SQL
  end
end
