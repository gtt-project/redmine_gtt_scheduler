class CreateSchedulerAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduler_assignments do |t|
      t.references :scheduler_run, null: false, index: true
      t.references :issue, null: false
      t.references :scheduler_resource, null: false
      t.integer :sequence, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :travel_seconds
      t.timestamps null: false
    end
    add_index :scheduler_assignments, [:scheduler_run_id, :issue_id], unique: true
  end
end
