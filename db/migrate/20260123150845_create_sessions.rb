class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :sessionable, polymorphic: true, null: false
      t.references :user, null: true, foreign_key: true  # nullable for now, will be used later
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :sessions, [:contract_id, :sessionable_type, :sessionable_id], name: 'index_sessions_on_contract_and_sessionable'
  end
end
