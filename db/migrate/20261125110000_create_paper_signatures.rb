# A signature made on paper: the signer uploads a scan of the signed document and the sending
# organization approves or returns it. Returned and canceled attempts stay as history, so only
# one paper signature per signer contract may be open (draft or submitted) at a time.
class CreatePaperSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :paper_signatures do |t|
      t.references :signer_contract, null: false, foreign_key: true
      t.string :uuid, null: false, index: { unique: true }
      t.string :status, null: false, default: "draft"
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :return_reason
      t.timestamps
    end

    add_index :paper_signatures, :signer_contract_id, unique: true,
      where: "status IN ('draft', 'submitted')", name: "index_paper_signatures_on_open_signer_contract_id"
  end
end
