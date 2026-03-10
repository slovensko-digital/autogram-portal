class RemoveUserFromDocuments < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :documents, :users
    remove_index :documents, :user_id
    remove_column :documents, :user_id, :bigint
  end
end
