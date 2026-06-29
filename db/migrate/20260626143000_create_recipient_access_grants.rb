class CreateRecipientAccessGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :recipient_access_grants do |t|
      t.uuid :uuid, null: false
      t.references :recipient, null: false, foreign_key: true
      t.references :portal_instance, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :revoked_at
      t.string :claimed_by_email, null: false
      t.string :claimed_by_external_user_id
      t.string :claim_jti, null: false

      t.timestamps
    end

    add_index :recipient_access_grants, :uuid, unique: true
    add_index :recipient_access_grants, :token_digest, unique: true
    add_index :recipient_access_grants, :expires_at
    add_index :recipient_access_grants, :claim_jti
  end
end
