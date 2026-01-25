class AddUuidToRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipients, :uuid, :uuid, null: false, default: 'gen_random_uuid()'
    add_index :recipients, :uuid, unique: true
  end
end
