class CreateAvmSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :avm_sessions do |t|
      t.references :contract, null: false, foreign_key: true
      t.string :document_id
      t.string :encryption_key
      t.datetime :signing_started_at
      t.datetime :completed_at
      t.string :status
      t.text :error_message

      t.timestamps
    end
  end
end
