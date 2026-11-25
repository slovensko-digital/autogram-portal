# Photos or a PDF of the signed pages, collected while the paper signature is a draft.
class CreatePaperSignaturePages < ActiveRecord::Migration[8.1]
  def change
    create_table :paper_signature_pages do |t|
      t.references :paper_signature, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end
  end
end
