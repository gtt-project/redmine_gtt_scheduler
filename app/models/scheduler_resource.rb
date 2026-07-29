class SchedulerResource < ApplicationRecord
  TIME_OF_DAY = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

  belongs_to :project
  belongs_to :user, optional: true
  has_many :scheduler_assignments, dependent: :restrict_with_error

  validates :name, presence: true, length: {maximum: 255}
  validates :start_lng, :start_lat, presence: true, numericality: true
  validates :end_lng, :end_lat, numericality: true, allow_nil: true
  validates :work_starts, :work_ends, presence: true, format: {with: TIME_OF_DAY}
  validate :validate_work_range

  scope :active, -> { where(active: true) }
  scope :sorted, -> { order(:name) }

  # [lon, lat] pairs for the solver; the end location defaults to the
  # start location when not set.
  def start_location
    [start_lng, start_lat]
  end

  def end_location
    end_lng && end_lat ? [end_lng, end_lat] : start_location
  end

  private

  def validate_work_range
    return unless work_starts.to_s.match?(TIME_OF_DAY) && work_ends.to_s.match?(TIME_OF_DAY)

    errors.add(:work_ends, :invalid) if work_ends <= work_starts
  end
end
