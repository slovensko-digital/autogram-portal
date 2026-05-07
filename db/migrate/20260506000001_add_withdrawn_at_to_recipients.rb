class AddWithdrawnAtToRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipients, :withdrawn_at, :datetime

    remove_index :recipients, [ :bundle_id, :email ]

    add_index :recipients, [ :bundle_id, :withdrawn_at ]
    add_index :recipients,
      [ :bundle_id, :email ],
      unique: true,
      where: "withdrawn_at IS NULL",
      name: "index_recipients_on_bundle_id_and_email_active"
  end
end
