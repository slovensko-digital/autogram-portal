class CreateSignatureVerificationsAndEvidenceRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :signature_verifications do |t|
      t.references :session, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :state, null: false, default: "pending"
      t.string :provider_request_id
      t.string :code_digest, null: false
      t.string :destination_digest, null: false
      t.string :last_request_ip
      t.string :last_user_agent
      t.datetime :sent_at
      t.datetime :verified_at
      t.datetime :expires_at
      t.integer :attempts_count, null: false, default: 0
      t.timestamps
    end

    add_index :signature_verifications, :state
    add_index :signature_verifications, :expires_at

    create_table :signature_evidence_records do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :session, null: false, foreign_key: true
      t.references :signer_contract, null: false, foreign_key: true
      t.references :contract_content_version, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.jsonb :canonical_payload, null: false, default: {}
      t.string :payload_sha256
      t.text :signed_manifest
      t.string :manifest_sha256
      t.string :public_reference, null: false
      t.datetime :locked_at
      t.timestamps
    end

    add_index :signature_evidence_records, :uuid, unique: true
    add_index :signature_evidence_records, :public_reference, unique: true
    add_index :signature_evidence_records, :state
  end
end
