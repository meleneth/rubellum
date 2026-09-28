class CreateExecutionTransport < ActiveRecord::Migration[8.1]
  def change
    create_table :notebook_sessions, id: :uuid do |t|
      t.references :notebook, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.integer :generation, null: false, default: 1
      t.bigint :next_command_sequence, null: false, default: 1
      t.string :status, null: false, default: "requested"
      t.timestamps
    end
    create_table :executions, id: :uuid do |t|
      t.references :notebook_session, type: :uuid, null: false, foreign_key: true
      t.references :cell_revision, type: :uuid, null: false, foreign_key: true
      t.references :notebook_revision, type: :uuid, null: false, foreign_key: true
      t.integer :generation, null: false
      t.bigint :sequence, null: false
      t.jsonb :inputs, null: false, default: {}
      t.jsonb :datasets, null: false, default: {}
      t.string :environment_digest, null: false
      t.string :status, null: false, default: "queued"
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :executions, [:notebook_session_id, :generation, :sequence], unique: true, name: "unique_execution_order"
    create_table :outbox_messages, id: :uuid do |t|
      t.string :queue_name, null: false
      t.jsonb :envelope, null: false
      t.datetime :sent_at
      t.datetime :confirmed_at
      t.timestamps
    end
    create_table :runner_events, id: :uuid do |t|
      t.references :notebook_session, type: :uuid, null: false, foreign_key: true
      t.integer :generation, null: false
      t.bigint :sequence, null: false
      t.jsonb :envelope, null: false
      t.datetime :created_at, null: false
    end
    add_index :runner_events, [:notebook_session_id, :generation, :sequence], unique: true, name: "unique_runner_event_order"
    create_table :event_cursors do |t|
      t.references :notebook_session, type: :uuid, null: false, foreign_key: true
      t.integer :generation, null: false
      t.bigint :through_sequence, null: false, default: 0
    end
    add_index :event_cursors, [:notebook_session_id, :generation], unique: true
  end
end
