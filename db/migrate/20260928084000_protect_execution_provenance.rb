class ProtectExecutionProvenance < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION validate_execution_provenance() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM notebook_sessions s JOIN cells c ON c.notebook_id = s.notebook_id
          JOIN cell_revisions r ON r.cell_id = c.id
          JOIN notebook_revisions n ON n.notebook_id = s.notebook_id
          WHERE s.id = NEW.notebook_session_id AND r.id = NEW.cell_revision_id AND n.id = NEW.notebook_revision_id
          AND n.entries @> jsonb_build_array(jsonb_build_object('cell_id', c.id::text, 'revision_id', r.id::text))
        ) THEN
          RAISE EXCEPTION 'execution provenance does not match notebook snapshot' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER execution_provenance BEFORE INSERT ON executions
        FOR EACH ROW EXECUTE FUNCTION validate_execution_provenance();
      CREATE FUNCTION immutable_execution_request() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (to_jsonb(OLD) - 'status' - 'result' - 'updated_at') IS DISTINCT FROM
           (to_jsonb(NEW) - 'status' - 'result' - 'updated_at') THEN
          RAISE EXCEPTION 'execution request snapshot is immutable' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER execution_request_immutable BEFORE UPDATE ON executions
        FOR EACH ROW EXECUTE FUNCTION immutable_execution_request();
      CREATE TRIGGER runner_event_immutable BEFORE UPDATE OR DELETE ON runner_events
        FOR EACH ROW EXECUTE FUNCTION immutable_revision();
    SQL
    add_check_constraint :executions, "jsonb_typeof(inputs) = 'object' AND jsonb_typeof(datasets) = 'object'", name: "execution_input_objects"
    add_check_constraint :executions, "generation > 0 AND sequence > 0", name: "execution_positive_order"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
