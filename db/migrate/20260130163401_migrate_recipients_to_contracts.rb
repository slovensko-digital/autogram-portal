class MigrateRecipientsToContracts < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      INSERT INTO contracts_recipients (contract_id, recipient_id)
      SELECT c.id, r.id
      FROM recipients r
      INNER JOIN contracts c ON c.bundle_id = r.bundle_id
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM contracts_recipients"
  end
end
