class ProtectArtifactIdentity < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION validate_artifact_identity() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE payload jsonb;
      BEGIN
        IF NEW.runner_event_id IS NOT NULL THEN
          SELECT envelope->'payload' INTO payload FROM runner_events WHERE id = NEW.runner_event_id;
          IF payload->'blob'->>'sha256' IS DISTINCT FROM NEW.sha256 OR
             (payload->'blob'->>'size')::bigint IS DISTINCT FROM NEW.byte_size OR
             payload->>'filename' IS DISTINCT FROM NEW.filename THEN
            RAISE EXCEPTION 'artifact metadata does not match recorded event' USING ERRCODE = '23514';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER artifact_identity BEFORE INSERT ON assets FOR EACH ROW EXECUTE FUNCTION validate_artifact_identity();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
