class CreateImmutableAssets < ActiveRecord::Migration[8.1]
  def up
    create_table :assets, id: :uuid do |t|
      t.references :app, type: :uuid, null: false, foreign_key: true
      t.uuid :portable_id, null: false, default: -> { "gen_random_uuid()" }
      t.references :execution, type: :uuid, foreign_key: true
      t.references :runner_event, type: :uuid, foreign_key: true, index: { unique: true }
      t.string :filename, null: false
      t.string :mime_type, null: false
      t.string :sha256, null: false
      t.bigint :byte_size, null: false
      t.datetime :created_at, null: false
    end
    add_index :assets, [:app_id, :portable_id], unique: true
    add_check_constraint :assets, "sha256 ~ '^[0-9a-f]{64}$' AND byte_size BETWEEN 0 AND 26214400", name: "asset_content_identity"
    add_check_constraint :assets, "(execution_id IS NULL) = (runner_event_id IS NULL)", name: "artifact_provenance_pair"
    execute <<~SQL
      CREATE TRIGGER immutable_assets BEFORE UPDATE OR DELETE ON assets
        FOR EACH ROW EXECUTE FUNCTION immutable_revision();
      CREATE FUNCTION validate_asset_scope() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.execution_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM executions e JOIN notebook_sessions s ON s.id = e.notebook_session_id
          JOIN notebooks n ON n.id = s.notebook_id JOIN runner_events r ON r.id = NEW.runner_event_id
          WHERE e.id = NEW.execution_id AND n.app_id = NEW.app_id AND r.notebook_session_id = s.id
            AND r.generation = e.generation AND r.envelope->>'kind' = 'artifact'
            AND r.envelope->>'execution_id' = e.id::text
        ) THEN
          RAISE EXCEPTION 'artifact provenance does not match app/execution' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER asset_scope BEFORE INSERT ON assets FOR EACH ROW EXECUTE FUNCTION validate_asset_scope();

      CREATE FUNCTION validate_revision_assets() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE owner uuid; asset_id text; references_json jsonb; source_match text[];
      BEGIN
        IF TG_TABLE_NAME = 'cell_revisions' THEN
          SELECT n.app_id INTO owner FROM cells c JOIN notebooks n ON n.id = c.notebook_id WHERE c.id = NEW.cell_id;
          FOR source_match IN SELECT regexp_matches(NEW.source, 'asset://([a-zA-Z0-9-]+)', 'g') LOOP
            IF NOT EXISTS (SELECT 1 FROM assets WHERE id::text = source_match[1] AND app_id = owner) THEN
              RAISE EXCEPTION 'missing or cross-app asset reference' USING ERRCODE = '23514';
            END IF;
          END LOOP;
        ELSE
          owner := NEW.app_id;
        END IF;
        references_json := COALESCE(NEW.configuration->'asset_ids', '[]'::jsonb);
        IF jsonb_typeof(references_json) <> 'array' THEN
          RAISE EXCEPTION 'asset_ids must be an array' USING ERRCODE = '23514';
        END IF;
        FOR asset_id IN SELECT jsonb_array_elements_text(references_json) LOOP
          IF NOT EXISTS (SELECT 1 FROM assets WHERE id::text = asset_id AND app_id = owner) THEN
            RAISE EXCEPTION 'missing or cross-app asset reference' USING ERRCODE = '23514';
          END IF;
        END LOOP;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER cell_asset_references BEFORE INSERT ON cell_revisions FOR EACH ROW EXECUTE FUNCTION validate_revision_assets();
      CREATE TRIGGER app_asset_references BEFORE INSERT ON app_revisions FOR EACH ROW EXECUTE FUNCTION validate_revision_assets();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Assets referenced by retained history must not be dropped"
  end
end
