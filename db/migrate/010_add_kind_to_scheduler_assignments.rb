class AddKindToSchedulerAssignments < ActiveRecord::Migration[7.2]
  def change
    # 'pickup' or 'delivery' for a stop that is half of a shipment;
    # NULL for a plain job stop.
    add_column :scheduler_assignments, :kind, :string
  end
end
