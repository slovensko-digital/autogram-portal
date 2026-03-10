class EnforceSingleRecipientSignerPerRecipient < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TEMP TABLE recipient_signer_dedup_map (
        loser_id bigint PRIMARY KEY,
        winner_id bigint NOT NULL
      ) ON COMMIT DROP;

      WITH ranked AS (
        SELECT
          s.id AS signer_id,
          s.recipient_id,
          MAX(sc.signed_at) AS latest_signed_at,
          ROW_NUMBER() OVER (
            PARTITION BY s.recipient_id
            ORDER BY MAX(sc.signed_at) DESC NULLS LAST, s.id DESC
          ) AS rn
        FROM signers s
        LEFT JOIN signer_contracts sc ON sc.signer_id = s.id
        WHERE s.type = 'RecipientSigner' AND s.recipient_id IS NOT NULL
        GROUP BY s.id, s.recipient_id
      ),
      winners AS (
        SELECT recipient_id, signer_id
        FROM ranked
        WHERE rn = 1
      ),
      losers AS (
        SELECT recipient_id, signer_id
        FROM ranked
        WHERE rn > 1
      )
      INSERT INTO recipient_signer_dedup_map (loser_id, winner_id)
      SELECT losers.signer_id, winners.signer_id
      FROM losers
      INNER JOIN winners USING (recipient_id);
    SQL

    execute <<~SQL
      UPDATE signer_contracts winner_sc
      SET signed_at = COALESCE(
        GREATEST(winner_sc.signed_at, loser_sc.signed_at),
        winner_sc.signed_at,
        loser_sc.signed_at
      )
      FROM signer_contracts loser_sc
      INNER JOIN recipient_signer_dedup_map map ON map.loser_id = loser_sc.signer_id
      WHERE winner_sc.signer_id = map.winner_id
        AND winner_sc.contract_id = loser_sc.contract_id;
    SQL

    execute <<~SQL
      UPDATE sessions sess
      SET signer_contract_id = winner_sc.id
      FROM signer_contracts loser_sc
      INNER JOIN recipient_signer_dedup_map map ON map.loser_id = loser_sc.signer_id
      INNER JOIN signer_contracts winner_sc
        ON winner_sc.signer_id = map.winner_id
       AND winner_sc.contract_id = loser_sc.contract_id
      WHERE sess.signer_contract_id = loser_sc.id;
    SQL

    execute <<~SQL
      DELETE FROM signer_contracts loser_sc
      USING recipient_signer_dedup_map map, signer_contracts winner_sc
      WHERE loser_sc.signer_id = map.loser_id
        AND winner_sc.signer_id = map.winner_id
        AND winner_sc.contract_id = loser_sc.contract_id;
    SQL

    execute <<~SQL
      UPDATE signer_contracts sc
      SET signer_id = map.winner_id
      FROM recipient_signer_dedup_map map
      WHERE sc.signer_id = map.loser_id;
    SQL

    execute <<~SQL
      DELETE FROM signers s
      USING recipient_signer_dedup_map map
      WHERE s.id = map.loser_id;
    SQL

    add_index :signers,
              :recipient_id,
              unique: true,
              where: "type = 'RecipientSigner' AND recipient_id IS NOT NULL",
              name: :index_signers_on_recipient_id_unique_for_recipient_signers
  end

  def down
    remove_index :signers, name: :index_signers_on_recipient_id_unique_for_recipient_signers
  end
end
