class TrackPendingSessionReset < ActiveRecord::Migration[8.1]
  def change
    add_column :notebook_sessions, :restart_generation, :integer
    add_check_constraint :notebook_sessions,
      "restart_generation IS NULL OR restart_generation = generation + 1",
      name: "session_pending_next_generation"
  end
end
