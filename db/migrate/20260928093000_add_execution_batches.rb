class AddExecutionBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :executions, :batch_id, :uuid
    add_index :executions, :batch_id
  end
end
