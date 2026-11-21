# The tenant API accepts each token (its jti) only once, so a leaked token cannot be replayed.
# A row is needed only until its token expires; ApiTokenUsesCleanupJob deletes it afterwards.
class CreateApiTokenUses < ActiveRecord::Migration[8.1]
  def change
    create_table :api_token_uses do |t|
      t.references :tenant, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :jti, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :api_token_uses, [ :tenant_id, :jti ], unique: true
    add_index :api_token_uses, :expires_at
  end
end
