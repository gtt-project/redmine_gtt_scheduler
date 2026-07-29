# Which resources a run was asked to plan with. A run with no rows falls back to
# every active resource, which is what runs created before this table did.
class SchedulerRunResource < ApplicationRecord
  belongs_to :scheduler_run
  belongs_to :scheduler_resource

  validates :scheduler_resource_id, uniqueness: {scope: :scheduler_run_id}
end
