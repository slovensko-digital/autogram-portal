class MigrateRecipientsToContracts < ActiveRecord::Migration[8.1]
  def up
    # For each recipient, associate them with all contracts in their bundle
    execute <<-SQL
      INSERT INTO contracts_recipients (contract_id, recipient_id)
      SELECT c.id, r.id
      FROM recipients r
      INNER JOIN contracts c ON c.bundle_id = r.bundle_id
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    # Remove all contract-recipient associations
    execute "DELETE FROM contracts_recipients"
  end
end
