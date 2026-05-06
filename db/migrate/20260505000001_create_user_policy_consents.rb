class CreateUserPolicyConsents < ActiveRecord::Migration[8.0]
  def change
    create_table :user_policy_consents do |t|
      t.references :user, null: false, foreign_key: true

      t.string :policy_type,    null: false  # "terms" / "privacy"
      t.string :policy_version, null: false
      t.string :source,         null: false  # "email_signup" / "google_oauth2" / "re_consent"
      t.datetime :accepted_at,  null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :user_policy_consents, [ :user_id, :policy_type, :policy_version ],
              name: "index_user_policy_consents_on_user_policy_version"
    add_index :user_policy_consents, [ :user_id, :accepted_at ]
  end
end
