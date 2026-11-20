# Anonymous usage statistics (documents uploaded and signed) for BI tools such as Metabase. Events outlive
# the documents, which retention deletes, so they keep the tenant id without a foreign key.
class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.string :kind, null: false
      t.string :plan, null: false
      t.string :channel
      t.string :signing_method
      t.bigint :tenant_id
      t.integer :documents_count
      t.bigint :byte_size
      t.datetime :created_at, null: false
    end

    add_index :activity_events, [ :kind, :created_at ]
    add_index :activity_events, :tenant_id

    reversible do |direction|
      direction.up { backfill }
    end
  end

  private

  # Documents and signatures that still exist, with the current plan of their tenant and no channel,
  # which is unknown for them.
  def backfill
    execute <<~SQL
      INSERT INTO activity_events (kind, plan, tenant_id, documents_count, byte_size, created_at)
      SELECT 'document_uploaded', coalesce(tenants.plan, 'anonymous'), contracts.tenant_id,
             count(documents.id), coalesce(sum(active_storage_blobs.byte_size), 0), contracts.created_at
      FROM contracts
      LEFT JOIN tenants ON tenants.id = contracts.tenant_id
      LEFT JOIN documents ON documents.contract_id = contracts.id
      LEFT JOIN active_storage_attachments ON active_storage_attachments.record_type = 'Document'
        AND active_storage_attachments.name = 'blob' AND active_storage_attachments.record_id = documents.id
      LEFT JOIN active_storage_blobs ON active_storage_blobs.id = active_storage_attachments.blob_id
      GROUP BY contracts.id, tenants.plan
    SQL

    # AdesEvidenceSession -> ades_evidence, as ActivityEvent.signing_method_for
    execute <<~SQL
      INSERT INTO activity_events (kind, plan, tenant_id, signing_method, created_at)
      SELECT 'document_signed', coalesce(tenants.plan, 'anonymous'), contracts.tenant_id,
             lower(regexp_replace(left(sessions.type, -length('Session')), '([a-z])([A-Z])', '\\1_\\2', 'g')),
             coalesce(sessions.completed_at, sessions.updated_at)
      FROM sessions
      JOIN signer_contracts ON signer_contracts.id = sessions.signer_contract_id
      JOIN contracts ON contracts.id = signer_contracts.contract_id
      LEFT JOIN tenants ON tenants.id = contracts.tenant_id
      WHERE sessions.status = 1
    SQL
  end
end
