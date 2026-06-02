class AddAuthorProxyToRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipients, :author_proxy, :boolean, null: false, default: false
    add_index :recipients, [ :bundle_id, :author_proxy, :withdrawn_at ]
  end
end
