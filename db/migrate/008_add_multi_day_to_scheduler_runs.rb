class AddMultiDayToSchedulerRuns < ActiveRecord::Migration[7.2]
  def change
    # Last day of the planning range; NULL means a single-day run, which
    # is what every run before this column was.
    add_column :scheduler_runs, :scheduled_until, :date

    # JSON map of solver vehicle id => [resource id, ISO date]. Multi-day
    # runs use one synthetic vehicle per resource per working day, and
    # anything reading the stored solver response (route geometry) needs
    # this to get back to the resource. NULL for single-day runs, whose
    # vehicle ids are the resource ids.
    add_column :scheduler_runs, :vehicle_map, :text
  end
end
