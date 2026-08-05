class AddWorkingDaysToSchedulerResources < ActiveRecord::Migration[7.2]
  def change
    # JSON array of ISO weekday numbers (1 = Monday .. 7 = Sunday) the
    # resource works on. NULL / empty means every day, which is what the
    # behaviour was before this column existed, so old rows need no
    # backfill.
    add_column :scheduler_resources, :working_days, :text
  end
end
