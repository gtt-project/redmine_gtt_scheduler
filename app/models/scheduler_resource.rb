class SchedulerResource < ApplicationRecord
  TIME_OF_DAY = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

  # Skill names this resource offers, from the vocabulary of the custom
  # field configured in the plugin settings. Names, not ids: solver ids
  # are assigned per request (see ProblemBuilder), so admins can rename
  # or reorder the custom field values freely.
  serialize :skills, coder: JSON, type: Array

  # ISO weekday numbers (1 = Monday .. 7 = Sunday) this resource works
  # on. Empty means every day; see works_on?.
  serialize :working_days, coder: JSON, type: Array

  belongs_to :project
  belongs_to :user, optional: true
  has_many :scheduler_assignments, dependent: :restrict_with_error

  validates :name, presence: true, length: {maximum: 255}
  validates :start_lng, :start_lat, presence: true, numericality: true
  validates :end_lng, :end_lat, numericality: true, allow_nil: true
  validates :work_starts, :work_ends, presence: true, format: {with: TIME_OF_DAY}
  validates :capacity, numericality: {only_integer: true, greater_than_or_equal_to: 0},
                       allow_nil: true
  validates :break_starts, :break_ends, format: {with: TIME_OF_DAY}, allow_blank: true
  validates :break_minutes, numericality: {only_integer: true, greater_than: 0},
                            allow_nil: true
  validate :validate_break
  validate :validate_work_range

  scope :active, -> { where(active: true) }
  scope :sorted, -> { order(:name) }

  # The form submits a hidden blank entry so an empty selection clears
  # the list; strip it and any accidental non-strings here.
  def skills=(value)
    super(Array(value).map(&:to_s).reject(&:blank?))
  end

  def working_days=(value)
    super(Array(value).map(&:to_i).select { |day| (1..7).cover?(day) }.uniq.sort)
  end

  # No selection means every day: that is what the behaviour was before
  # working days existed, so rows from that time (stored as NULL) keep
  # it, and it follows the plugin's convention that an empty selection
  # means "no restriction" (compare the run's resource selection).
  def works_on?(date)
    working_days.empty? || working_days.include?(date.cwday)
  end

  # The daily break is on only when the whole triple is set; a partial
  # configuration is rejected by validation rather than half-applied.
  def break?
    break_starts.present? && break_ends.present? && break_minutes.present?
  end

  # [lon, lat] pairs for the solver; the end location defaults to the
  # start location when not set.
  def start_location
    [start_lng, start_lat]
  end

  def end_location
    end_lng && end_lat ? [end_lng, end_lat] : start_location
  end

  # Minutes since midnight, or nil when the value is not a valid time.
  # Compared numerically because "8:00" sorts after "17:00" as a string.
  def self.minutes_of_day(value)
    match = TIME_OF_DAY.match(value.to_s)
    match && (match[1].to_i * 60) + match[2].to_i
  end

  private

  def validate_work_range
    starts = self.class.minutes_of_day(work_starts)
    ends = self.class.minutes_of_day(work_ends)
    return if starts.nil? || ends.nil?

    errors.add(:work_ends, :invalid) if ends <= starts
  end

  def validate_break
    fields = [break_starts.presence, break_ends.presence, break_minutes.presence]
    if fields.any? && !fields.all?
      errors.add(:base, :scheduler_break_incomplete)
      return
    end
    return unless break?

    starts = self.class.minutes_of_day(break_starts)
    ends = self.class.minutes_of_day(break_ends)
    return if starts.nil? || ends.nil?

    errors.add(:break_ends, :invalid) if ends <= starts
  end
end
