class CreateFederationRequestInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :federation_request_invitations do |t|
      t.uuid :uuid, null: false
      t.references :portal_instance, null: false, foreign_key: true
      t.uuid :origin_recipient_uuid, null: false
      t.uuid :origin_bundle_uuid, null: false
      t.string :recipient_email, null: false
      t.references :recipient_user, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.datetime :withdrawn_at
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :federation_request_invitations, :uuid, unique: true
    add_index :federation_request_invitations, [ :portal_instance_id, :origin_recipient_uuid ], unique: true, name: "index_federation_request_invitations_on_portal_and_recipient"
    add_index :federation_request_invitations, :recipient_email
    add_index :federation_request_invitations, :status
  end
end
