class AddRecipientContractToSessions < ActiveRecord::Migration[8.1]
  def up
    add_reference :sessions, :recipient_contract, null: true, foreign_key: true

    # Backfill recipient_contract_id for sessions that already have recipient_id
    execute <<~SQL
      UPDATE sessions
      SET recipient_contract_id = rc.id
      FROM recipient_contracts rc
      WHERE rc.recipient_id = sessions.recipient_id
        AND rc.contract_id = sessions.contract_id
    SQL

    # For bundle-contract sessions without a recipient_id (author signed directly):
    # create a Recipient row for that user in the bundle, then link via RecipientContract.

    # Step 1: create missing Recipient rows
    execute <<~SQL
      INSERT INTO recipients (bundle_id, email, uuid, status, notification_status, locale, user_id, created_at, updated_at)
      SELECT DISTINCT c.bundle_id, u.email, gen_random_uuid(), 0, 0, COALESCE(u.locale, 'sk'), u.id, NOW(), NOW()
      FROM sessions s
      JOIN contracts c ON c.id = s.contract_id
      JOIN users u     ON u.id = s.user_id
      WHERE s.recipient_id IS NULL
        AND s.recipient_contract_id IS NULL
        AND c.bundle_id IS NOT NULL
      ON CONFLICT (bundle_id, email) DO NOTHING
    SQL

    # Step 2: create RecipientContract rows for those recipients
    execute <<~SQL
      INSERT INTO recipient_contracts (recipient_id, contract_id, created_at, updated_at)
      SELECT DISTINCT r.id, s.contract_id, NOW(), NOW()
      FROM sessions s
      JOIN contracts c  ON c.id = s.contract_id
      JOIN users u      ON u.id = s.user_id
      JOIN recipients r ON r.bundle_id = c.bundle_id AND r.email = u.email
      WHERE s.recipient_id IS NULL
        AND s.recipient_contract_id IS NULL
        AND c.bundle_id IS NOT NULL
      ON CONFLICT (recipient_id, contract_id) DO NOTHING
    SQL

    # Step 3: backfill recipient_contract_id for those sessions
    execute <<~SQL
      UPDATE sessions
      SET recipient_contract_id = rc.id
      FROM recipient_contracts rc
      JOIN recipients r ON r.id = rc.recipient_id
      JOIN users u      ON u.email = r.email
      JOIN contracts c  ON c.id = rc.contract_id AND c.bundle_id = r.bundle_id
      WHERE sessions.contract_id = rc.contract_id
        AND sessions.user_id = u.id
        AND sessions.recipient_id IS NULL
        AND sessions.recipient_contract_id IS NULL
        AND c.bundle_id IS NOT NULL
    SQL

    # Backfill signed_at on recipient_contracts from already-signed sessions
    execute <<~SQL
      UPDATE recipient_contracts
      SET signed_at = sessions.completed_at
      FROM sessions
      WHERE sessions.recipient_contract_id = recipient_contracts.id
        AND sessions.status = 1
        AND recipient_contracts.signed_at IS NULL
    SQL

    remove_column :sessions, :recipient_id
  end

  def down
    add_column :sessions, :recipient_id, :bigint
    add_index :sessions, :recipient_id
    add_foreign_key :sessions, :recipients

    execute <<~SQL
      UPDATE sessions
      SET recipient_id = rc.recipient_id
      FROM recipient_contracts rc
      WHERE rc.id = sessions.recipient_contract_id
    SQL

    remove_reference :sessions, :recipient_contract
  end
end
