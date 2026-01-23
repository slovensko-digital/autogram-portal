class RemoveContractFromSessionables < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      INSERT INTO sessions (contract_id, sessionable_type, sessionable_id, status, created_at, updated_at)
      SELECT contract_id, 'EidentitaSession', id,
        CASE status
          WHEN 'pending' THEN 0
          WHEN 'completed' THEN 1
          WHEN 'failed' THEN 2
          WHEN 'expired' THEN 3
        END as status,
        created_at, updated_at
      FROM eidentita_sessions
    SQL

    execute <<-SQL
      INSERT INTO sessions (contract_id, sessionable_type, sessionable_id, status, created_at, updated_at)
      SELECT contract_id, 'AvmSession', id,
        CASE status
          WHEN 'pending' THEN 0
          WHEN 'completed' THEN 1
          WHEN 'failed' THEN 2
          WHEN 'expired' THEN 3
        END as status,
        created_at, updated_at
      FROM avm_sessions
    SQL

    remove_reference :eidentita_sessions, :contract, foreign_key: true, index: true
    remove_column :eidentita_sessions, :status, :string

    remove_reference :avm_sessions, :contract, foreign_key: true, index: true
    remove_column :avm_sessions, :status, :string

    remove_reference :autogram_sessions, :contract, foreign_key: true, index: true
    remove_column :autogram_sessions, :status, :integer
  end

  def down
    add_column :eidentita_sessions, :status, :string
    add_reference :eidentita_sessions, :contract, foreign_key: true, index: true
    add_column :avm_sessions, :status, :string
    add_reference :avm_sessions, :contract, foreign_key: true, index: true
    add_column :autogram_sessions, :status, :integer
    add_reference :autogram_sessions, :contract, foreign_key: true, index: true
  end
end
