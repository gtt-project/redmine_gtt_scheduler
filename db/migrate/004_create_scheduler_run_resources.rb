class CreateSchedulerRunResources < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduler_run_resources do |t|
      t.references :scheduler_run, null: false, index: true
      t.references :scheduler_resource, null: false
    end
    add_index :scheduler_run_resources,
              [:scheduler_run_id, :scheduler_resource_id],
              unique: true,
              name: 'index_scheduler_run_resources_unique'
  end
end
