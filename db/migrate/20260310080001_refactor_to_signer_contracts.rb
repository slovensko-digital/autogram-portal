class RefactorToSignerContracts < ActiveRecord::Migration[8.1]
  def up
    # ── Phase 1: Populate signers table ────────────────────────────────────

    # One RecipientSigner per distinct recipient referenced in recipient_contracts
    execute <<~SQL
      INSERT INTO signers (type, recipient_id, created_at, updated_at)
      SELECT DISTINCT 'RecipientSigner', recipient_id, NOW(), NOW()
      FROM recipient_contracts
    SQL

    # One UserSigner per distinct user_id on standalone sessions
    # (sessions that have no recipient_contract, i.e. direct user signing)
    execute <<~SQL
      INSERT INTO signers (type, user_id, created_at, updated_at)
      SELECT DISTINCT 'UserSigner', user_id, NOW(), NOW()
      FROM sessions
      WHERE user_id IS NOT NULL AND recipient_contract_id IS NULL
    SQL

    # ── Phase 2: Add signer_id to recipient_contracts ──────────────────────

    add_column :recipient_contracts, :signer_id, :bigint
    add_index  :recipient_contracts, :signer_id

    # Backfill signer_id for existing RecipientSigner rows
    execute <<~SQL
      UPDATE recipient_contracts rc
      SET    signer_id = s.id
      FROM   signers s
      WHERE  s.type = 'RecipientSigner'
        AND  s.recipient_id = rc.recipient_id
    SQL

    # Make recipient_id nullable so we can insert UserSigner-backed rows below
    change_column_null :recipient_contracts, :recipient_id, true

    # Insert one SignerContract per standalone (user_id, contract_id) session pair
    execute <<~SQL
      INSERT INTO recipient_contracts (signer_id, contract_id, created_at, updated_at)
      SELECT DISTINCT s.id, sess.contract_id, NOW(), NOW()
      FROM   sessions sess
      JOIN   signers  s  ON s.type = 'UserSigner' AND s.user_id = sess.user_id
      WHERE  sess.recipient_contract_id IS NULL
        AND  sess.user_id IS NOT NULL
    SQL

    # ── Phase 3: Add signer_contract_id to sessions ────────────────────────

    add_column :sessions, :signer_contract_id, :bigint
    add_index  :sessions, :signer_contract_id

    # Copy recipient_contract_id → signer_contract_id (same IDs, table is just renamed later)
    execute <<~SQL
      UPDATE sessions
      SET    signer_contract_id = recipient_contract_id
      WHERE  recipient_contract_id IS NOT NULL
    SQL

    # Backfill signer_contract_id for standalone sessions via the newly inserted rows
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

    # ── Phase 4: Drop old FKs from sessions before renaming the table ──────

    remove_foreign_key :sessions, column: :recipient_contract_id
    remove_foreign_key :sessions, column: :contract_id
    remove_foreign_key :sessions, column: :user_id

    # ── Phase 5: Rename recipient_contracts → signer_contracts ────────────
    # NOTE: Rails rename_table also renames all convention-named indexes, so
    # after this point index names carry the "signer_contracts" prefix.

    rename_table :recipient_contracts, :signer_contracts

    # Add FK: signer_contracts.signer_id → signers.id
    add_foreign_key :signer_contracts, :signers, column: :signer_id

    # Drop the old recipient_id FK and its indexes, then the column itself.
    # Index names have already been updated by rename_table above.
    remove_foreign_key :signer_contracts, column: :recipient_id
    remove_index :signer_contracts, name: "index_signer_contracts_on_recipient_id_and_contract_id"
    remove_index :signer_contracts, name: "index_signer_contracts_on_recipient_id"
    remove_column :signer_contracts, :recipient_id

    add_index :signer_contracts, [ :signer_id, :contract_id ], unique: true

    # ── Phase 6: Wire up signer_contract_id on sessions ───────────────────

    add_foreign_key :sessions, :signer_contracts, column: :signer_contract_id

    # Delete orphaned sessions that have no signer linkage (no user_id, no
    # recipient_contract_id) — these are dead dev/test data with no path to
    # a SignerContract, so they cannot be migrated forward.
    execute "DELETE FROM sessions WHERE signer_contract_id IS NULL"

    change_column_null :sessions, :signer_contract_id, false

    # Remove the now-redundant old columns from sessions
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
