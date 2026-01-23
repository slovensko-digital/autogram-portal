class CreateAutogramSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :autogram_sessions do |t|
      t.references :contract, null: false, foreign_key: true
      t.datetime :signing_started_at
      t.integer :status, default: 0, null: false
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end
  end
end
