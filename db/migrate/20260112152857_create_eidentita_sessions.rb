class CreateEidentitaSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :eidentita_sessions do |t|
      t.references :contract, null: false, foreign_key: true
      t.datetime :signing_started_at
      t.string :status
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end
  end
end
