class CreateNotebookHistory < ActiveRecord::Migration[8.1]
  def up
    create_table :apps, id: :uuid do |t|
      t.uuid :portable_id, null: false, default: -> { "gen_random_uuid()" }
      t.uuid :head_revision_id
      t.datetime :archived_at
      t.timestamps
    end
    create_table :notebooks, id: :uuid do |t|
      t.references :app, type: :uuid, null: false, foreign_key: true
      t.uuid :portable_id, null: false, default: -> { "gen_random_uuid()" }
      t.uuid :head_revision_id
      t.timestamps
    end
    add_index :notebooks, [:app_id, :portable_id], unique: true
    add_index :notebooks, [:id, :app_id], unique: true
    create_table :cells, id: :uuid do |t|
      t.references :notebook, type: :uuid, null: false, foreign_key: true
      t.uuid :portable_id, null: false, default: -> { "gen_random_uuid()" }
      t.uuid :head_revision_id
      t.timestamps
    end
    add_index :cells, [:notebook_id, :portable_id], unique: true

    create_table :app_revisions, id: :uuid do |t|
      t.references :app, type: :uuid, null: false, foreign_key: true
      t.uuid :parent_id
      t.string :title, null: false
      t.text :description, null: false, default: ""
      t.uuid :landing_notebook_id
      revision_columns(t)
    end
    create_table :cell_revisions, id: :uuid do |t|
      t.references :cell, type: :uuid, null: false, foreign_key: true
      t.uuid :parent_id
      t.string :cell_type, null: false
      t.string :title, null: false, default: ""
      t.text :source, null: false, default: ""
      revision_columns(t)
    end
    add_check_constraint :cell_revisions, "cell_type IN ('markdown','ruby','d3','data','table','parameters')", name: "known_cell_type"
    create_table :notebook_revisions, id: :uuid do |t|
      t.references :notebook, type: :uuid, null: false, foreign_key: true
      t.uuid :parent_id
      t.string :title, null: false
      t.text :description, null: false, default: ""
      t.jsonb :entries, null: false, default: []
      revision_columns(t)
    end
    %w[app cell notebook].each do |owner|
      revisions = "#{owner}_revisions"
      add_index revisions, [:id, "#{owner}_id"], unique: true
      execute "ALTER TABLE #{revisions} ADD CONSTRAINT #{owner}_revision_parent FOREIGN KEY (parent_id, #{owner}_id) REFERENCES #{revisions}(id, #{owner}_id)"
      execute "ALTER TABLE #{owner.pluralize} ADD CONSTRAINT #{owner}_head_owner FOREIGN KEY (head_revision_id, id) REFERENCES #{revisions}(id, #{owner}_id)"
    end
    execute "ALTER TABLE app_revisions ADD CONSTRAINT landing_notebook_owner FOREIGN KEY (landing_notebook_id, app_id) REFERENCES notebooks(id, app_id)"

    execute <<~SQL
      CREATE FUNCTION immutable_revision() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'revision history is immutable' USING ERRCODE = '23514';
      END;
      $$;
      CREATE FUNCTION validate_notebook_entries() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE entry jsonb; seen uuid[] := '{}'; cell_identity uuid;
      BEGIN
        IF jsonb_typeof(NEW.entries) <> 'array' THEN
          RAISE EXCEPTION 'notebook entries must be an array' USING ERRCODE = '23514';
        END IF;
        FOR entry IN SELECT * FROM jsonb_array_elements(NEW.entries) LOOP
          cell_identity := (entry->>'cell_id')::uuid;
          IF cell_identity IS NULL OR cell_identity = ANY(seen) OR
             NOT EXISTS (SELECT 1 FROM cell_revisions r JOIN cells c ON c.id = r.cell_id
               WHERE r.id = (entry->>'revision_id')::uuid AND c.id = cell_identity AND c.notebook_id = NEW.notebook_id) THEN
            RAISE EXCEPTION 'invalid or duplicate notebook entry' USING ERRCODE = '23514';
          END IF;
          seen := array_append(seen, cell_identity);
        END LOOP;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER notebook_entry_integrity BEFORE INSERT ON notebook_revisions
        FOR EACH ROW EXECUTE FUNCTION validate_notebook_entries();
      CREATE FUNCTION immutable_document_identity() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (to_jsonb(OLD) - 'head_revision_id' - 'updated_at' - 'archived_at')
          IS DISTINCT FROM (to_jsonb(NEW) - 'head_revision_id' - 'updated_at' - 'archived_at') THEN
          RAISE EXCEPTION 'document identity and ownership are immutable' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
    %w[apps notebooks cells].each do |table|
      execute "CREATE TRIGGER identity_#{table} BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION immutable_document_identity()"
    end
    %w[app_revisions cell_revisions notebook_revisions].each do |table|
      execute "CREATE TRIGGER immutable_#{table} BEFORE UPDATE OR DELETE ON #{table} FOR EACH ROW EXECUTE FUNCTION immutable_revision()"
    end
    create_table :drafts, id: :uuid do |t|
      t.references :cell, type: :uuid, null: false, foreign_key: true
      t.uuid :editor_id, null: false
      t.uuid :base_revision_id, null: false
      t.text :source, null: false
      t.string :title, null: false, default: ""
      t.string :cell_type, null: false
      t.jsonb :configuration, null: false, default: {}
      t.timestamps
    end
    add_index :drafts, [:cell_id, :editor_id], unique: true
    execute "ALTER TABLE drafts ADD CONSTRAINT draft_base_owner FOREIGN KEY (base_revision_id, cell_id) REFERENCES cell_revisions(id, cell_id)"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Immutable history requires an explicit export and database restore"
  end

  private

  def revision_columns(table)
    table.jsonb :configuration, null: false, default: {}
    table.string :author, null: false, default: "Owner"
    table.string :summary, null: false, default: ""
    table.jsonb :provenance, null: false, default: {}
    table.string :content_digest, null: false
    table.datetime :created_at, null: false
  end
end
