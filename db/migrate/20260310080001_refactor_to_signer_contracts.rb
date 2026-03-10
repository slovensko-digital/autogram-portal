class RefactorToSignerContracts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO signers (type, recipient_id, created_at, updated_at)
      SELECT DISTINCT 'RecipientSigner', recipient_id, NOW(), NOW()
      FROM recipient_contracts
    SQL

    execute <<~SQL
      INSERT INTO signers (type, user_id, created_at, updated_at)
      SELECT DISTINCT 'UserSigner', user_id, NOW(), NOW()
      FROM sessions
      WHERE user_id IS NOT NULL AND recipient_contract_id IS NULL
    SQL

    add_column :recipient_contracts, :signer_id, :bigint
    add_index  :recipient_contracts, :signer_id

    execute <<~SQL
      UPDATE recipient_contracts rc
      SET    signer_id = s.id
      FROM   signers s
      WHERE  s.type = 'RecipientSigner'
        AND  s.recipient_id = rc.recipient_id
    SQL

    change_column_null :recipient_contracts, :recipient_id, true

    execute <<~SQL
      INSERT INTO recipient_contracts (signer_id, contract_id, created_at, updated_at)
      SELECT DISTINCT s.id, sess.contract_id, NOW(), NOW()
      FROM   sessions sess
      JOIN   signers  s  ON s.type = 'UserSigner' AND s.user_id = sess.user_id
      WHERE  sess.recipient_contract_id IS NULL
        AND  sess.user_id IS NOT NULL
    SQL

    add_column :sessions, :signer_contract_id, :bigint
    add_index  :sessions, :signer_contract_id

    execute <<~SQL
      UPDATE sessions
      SET    signer_contract_id = recipient_contract_id
      WHERE  recipient_contract_id IS NOT NULL
    SQL

    execute <<~SQL
      UPDATE sessions
      SET    signer_contract_id = rc.id
      FROM   recipient_contracts rc,
             signers s
      WHERE  s.id = rc.signer_id
        AND  s.type = 'UserSigner'
        AND  s.user_id = sessions.user_id
        AND  sessions.recipient_contract_id IS NULL
        AND  sessions.user_id IS NOT NULL
        AND  rc.contract_id = sessions.contract_id
    SQL

    remove_foreign_key :sessions, column: :recipient_contract_id
    remove_foreign_key :sessions, column: :contract_id
    remove_foreign_key :sessions, column: :user_id
    rename_table :recipient_contracts, :signer_contracts
    add_foreign_key :signer_contracts, :signers, column: :signer_id
    remove_foreign_key :signer_contracts, column: :recipient_id
    remove_index :signer_contracts, name: "index_signer_contracts_on_recipient_id_and_contract_id"
    remove_index :signer_contracts, name: "index_signer_contracts_on_recipient_id"
    remove_column :signer_contracts, :recipient_id
    add_index :signer_contracts, [ :signer_id, :contract_id ], unique: true
    add_foreign_key :sessions, :signer_contracts, column: :signer_contract_id
    execute "DELETE FROM sessions WHERE signer_contract_id IS NULL"
    change_column_null :sessions, :signer_contract_id, false
    remove_index  :sessions, name: "index_sessions_on_contract_id"
    remove_index  :sessions, name: "index_sessions_on_user_id"
    remove_index  :sessions, name: "index_sessions_on_recipient_contract_id"
    remove_column :sessions, :recipient_contract_id
    remove_column :sessions, :contract_id
    remove_column :sessions, :user_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
