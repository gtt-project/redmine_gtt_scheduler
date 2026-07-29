class SchedulerAssignment < ApplicationRecord
  belongs_to :scheduler_run
  belongs_to :issue
  belongs_to :scheduler_resource

  validates :sequence, :starts_at, :ends_at, presence: true
end
