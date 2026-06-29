class CreatePortalInstancesAndAddFederationToRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_instances do |t|
      t.uuid :uuid, null: false
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :issuer, null: false
      t.string :status, null: false, default: "verified"
      t.text :public_key_pem, null: false
      t.jsonb :capabilities, null: false, default: {}
      t.string :allowed_email_domains, array: true, null: false, default: []
      t.datetime :last_verified_at
      t.string :outbound_kid
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :portal_instances, :uuid, unique: true
    add_index :portal_instances, :issuer, unique: true
    add_index :portal_instances, :status

    add_reference :recipients, :portal_instance, foreign_key: true
    add_column :recipients, :federation_mode, :string, null: false, default: "local"
    add_column :recipients, :remote_claimed_at, :datetime
    add_column :recipients, :remote_claimed_by_email, :string
    add_index :recipients, :federation_mode

    add_check_constraint :recipients,
      "(federation_mode = 'local' AND portal_instance_id IS NULL) OR (federation_mode = 'federated' AND portal_instance_id IS NOT NULL)",
      name: "recipients_federation_mode_matches_portal_instance"
  end
end
