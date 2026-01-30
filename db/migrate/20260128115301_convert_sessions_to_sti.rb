class ConvertSessionsToSti < ActiveRecord::Migration[8.1]
  def up
    # Add new columns to sessions table
    add_column :sessions, :type, :string
    add_column :sessions, :signing_started_at, :datetime
    add_column :sessions, :completed_at, :datetime
    add_column :sessions, :error_message, :text
    add_column :sessions, :options, :jsonb, default: {}

    add_index :sessions, :type

    # Migrate data from eidentita_sessions
    execute <<-SQL
      UPDATE sessions
      SET type = 'EidentitaSession',
          signing_started_at = es.signing_started_at,
          completed_at = es.completed_at,
          error_message = es.error_message
      FROM eidentita_sessions es
      WHERE sessions.sessionable_type = 'EidentitaSession'
        AND sessions.sessionable_id = es.id
    SQL

    # Migrate data from avm_sessions
    execute <<-SQL
      UPDATE sessions
      SET type = 'AvmSession',
          signing_started_at = avm.signing_started_at,
          completed_at = avm.completed_at,
          error_message = avm.error_message,
          options = jsonb_build_object(
            'encryption_key', avm.encryption_key,
            'document_identifier', avm.document_id
          )
      FROM avm_sessions avm
      WHERE sessions.sessionable_type = 'AvmSession'
        AND sessions.sessionable_id = avm.id
    SQL

    # Migrate data from autogram_sessions
    execute <<-SQL
      UPDATE sessions
      SET type = 'AutogramSession',
          signing_started_at = ags.signing_started_at,
          completed_at = ags.completed_at,
          error_message = ags.error_message
      FROM autogram_sessions ags
      WHERE sessions.sessionable_type = 'AutogramSession'
        AND sessions.sessionable_id = ags.id
    SQL

    # Remove old polymorphic association columns
    remove_column :sessions, :sessionable_type
    remove_column :sessions, :sessionable_id

    # Drop old tables
    drop_table :eidentita_sessions
    drop_table :avm_sessions
    drop_table :autogram_sessions
  end

  def down
    # Recreate old tables
    create_table :eidentita_sessions do |t|
      t.datetime :signing_started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end

    create_table :avm_sessions do |t|
      t.string :document_id
      t.string :encryption_key
      t.datetime :signing_started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end

    create_table :autogram_sessions do |t|
      t.datetime :signing_started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end

    # Add back polymorphic columns
    add_column :sessions, :sessionable_type, :string
    add_column :sessions, :sessionable_id, :bigint

    # Migrate data back to eidentita_sessions
    execute <<-SQL
      INSERT INTO eidentita_sessions (id, signing_started_at, completed_at, error_message, created_at, updated_at)
      SELECT id, signing_started_at, completed_at, error_message, created_at, updated_at
      FROM sessions
      WHERE type = 'EidentitaSession'
    SQL

    execute <<-SQL
      UPDATE sessions
      SET sessionable_type = 'EidentitaSession',
          sessionable_id = id
      WHERE type = 'EidentitaSession'
    SQL

    # Migrate data back to avm_sessions
    execute <<-SQL
      INSERT INTO avm_sessions (id, document_id, encryption_key, signing_started_at, completed_at, error_message, created_at, updated_at)
      SELECT id,
             options->>'document_identifier',
             options->>'encryption_key',
             signing_started_at,
             completed_at,
             error_message,
             created_at,
             updated_at
      FROM sessions
      WHERE type = 'AvmSession'
    SQL

    execute <<-SQL
      UPDATE sessions
      SET sessionable_type = 'AvmSession',
          sessionable_id = id
      WHERE type = 'AvmSession'
    SQL

    # Migrate data back to autogram_sessions
    execute <<-SQL
      INSERT INTO autogram_sessions (id, signing_started_at, completed_at, error_message, created_at, updated_at)
      SELECT id, signing_started_at, completed_at, error_message, created_at, updated_at
      FROM sessions
      WHERE type = 'AutogramSession'
    SQL

    execute <<-SQL
      UPDATE sessions
      SET sessionable_type = 'AutogramSession',
          sessionable_id = id
      WHERE type = 'AutogramSession'
    SQL

    # Remove STI columns
    remove_index :sessions, :type
    remove_column :sessions, :type
    remove_column :sessions, :signing_started_at
    remove_column :sessions, :completed_at
    remove_column :sessions, :error_message
    remove_column :sessions, :options
  end
end
