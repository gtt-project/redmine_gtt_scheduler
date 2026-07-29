class CreateSchedulerResources < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduler_resources do |t|
      t.references :project, null: false, index: true
      t.references :user
      t.string :name, null: false
      t.float :start_lng, null: false
      t.float :start_lat, null: false
      t.float :end_lng
      t.float :end_lat
      t.string :work_starts, null: false, default: '08:00'
      t.string :work_ends, null: false, default: '17:00'
      t.boolean :active, null: false, default: true
      t.timestamps null: false
    end
  end
end
