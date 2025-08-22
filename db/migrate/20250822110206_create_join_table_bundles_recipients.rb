class CreateJoinTableBundlesRecipients < ActiveRecord::Migration[8.0]
  def change
    create_join_table :bundles, :recipients do |t|
      t.index [ :bundle_id, :recipient_id ]
      t.index [ :recipient_id, :bundle_id ]
    end

    add_foreign_key :bundles_recipients, :bundles
    add_foreign_key :bundles_recipients, :users, column: :recipient_id
  end
end
