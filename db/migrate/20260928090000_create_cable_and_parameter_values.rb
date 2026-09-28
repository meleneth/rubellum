class CreateCableAndParameterValues < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false
      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
    create_table :parameter_values, id: :uuid do |t|
      t.references :cell, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :values, null: false, default: {}
      t.timestamps
    end
  end
end
