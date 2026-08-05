class AddBreakToSchedulerResources < ActiveRecord::Migration[7.2]
  def change
    # Optional daily break: a window the break must be taken in (HH:MM
    # strings, like the working hours) and its duration. The break is on
    # only when all three are set.
    add_column :scheduler_resources, :break_starts, :string
    add_column :scheduler_resources, :break_ends, :string
    add_column :scheduler_resources, :break_minutes, :integer
  end
end
