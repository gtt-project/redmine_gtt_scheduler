class AddCapacityToSchedulerResources < ActiveRecord::Migration[7.2]
  def change
    # How much load this resource can carry in one run (single dimension).
    # NULL means unlimited.
    add_column :scheduler_resources, :capacity, :integer
  end
end
