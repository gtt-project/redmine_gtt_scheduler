class CreateSchedulerRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduler_runs do |t|
      t.references :project, null: false, index: true
      t.references :user, null: false
      t.date :scheduled_on, null: false
      t.string :status, null: false, default: 'draft'
      t.text :request_payload
      t.text :response_payload
      t.text :excluded_issues
      t.text :error_message
      t.timestamps null: false
    end
  end
end
