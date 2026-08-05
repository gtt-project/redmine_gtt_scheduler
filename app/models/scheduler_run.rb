class SchedulerRun < ApplicationRecord
  DRAFT = 'draft'.freeze
  SOLVING = 'solving'.freeze
  PROPOSED = 'proposed'.freeze
  APPLIED = 'applied'.freeze
  FAILED = 'failed'.freeze
  DISCARDED = 'discarded'.freeze
  STATUSES = [DRAFT, SOLVING, PROPOSED, APPLIED, FAILED, DISCARDED].freeze

  belongs_to :project
  belongs_to :user
  has_many :scheduler_assignments, dependent: :delete_all
  has_many :scheduler_run_resources, dependent: :delete_all
  has_many :selected_resources, through: :scheduler_run_resources,
                                source: :scheduler_resource

  # Guard on the problem size: every extra day multiplies the vehicle
  # count, and a mistyped year would otherwise ask the solver for
  # thousands of vehicles.
  MAX_PLANNING_DAYS = 14

  validates :scheduled_on, presence: true
  validates :status, inclusion: {in: STATUSES}
  validate :validate_planning_range

  scope :sorted, -> { order(id: :desc) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def discardable?
    proposed? || failed? || draft?
  end

  # The days this run plans. A run without an end date plans one day,
  # which is what every run was before multi-day planning existed.
  def planning_days
    (scheduled_on..(scheduled_until || scheduled_on)).to_a
  end

  def multi_day?
    scheduled_until.present? && scheduled_until > scheduled_on
  end

  # The resources this run plans with.
  #
  # The fallback is keyed on whether a selection was ever made, not on whether
  # it still yields anything: a run that selected two crews which have since
  # been deactivated must end up with no resources, not quietly inherit every
  # active one. Runs created before selection existed have no rows and keep
  # their original all-active behaviour.
  def resources_for_solving
    return selected_resources.active.sorted if resource_selection?

    project.scheduler_resources.active.sorted
  end

  def resource_selection?
    scheduler_run_resources.exists?
  end

  # Valid JSON is not necessarily a Hash: an array or a bare string parses fine
  # and would then raise on fetch, taking the run page down over stored data
  # rather than over anything the reader did.
  def parsed_response
    parsed = JSON.parse(response_payload.presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def excluded
    JSON.parse(excluded_issues.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  # Encoded route geometry per solver vehicle id, read back out of the
  # stored solver response so no extra column is needed. Empty for runs
  # solved without geometry, which the map handles by drawing straight
  # legs.
  def route_geometries
    response = parsed_response
    response.fetch('routes', []).each_with_object({}) do |route, out|
      out[route['vehicle']] = route['geometry'] if route['geometry'].present?
    end
  end

  # The same geometries grouped per resource, each with the ISO date of
  # the day it belongs to: a multi-day run has one solver vehicle (and so
  # one route) per resource per working day. For single-day runs, whose
  # vehicle ids are the resource ids, the map is absent, the vehicle id
  # is used directly, and the date is nil.
  # => { resource_id => [{'date' => '2026-08-03'|nil, 'geometry' => '...'}] }
  def route_geometries_by_resource
    map = parsed_vehicle_map
    route_geometries.each_with_object({}) do |(vehicle_id, geometry), out|
      resource_id, date = map[vehicle_id] || [vehicle_id, nil]
      (out[resource_id] ||= []) << {'date' => date, 'geometry' => geometry}
    end
  end

  # => { solver vehicle id => [resource id, ISO date string] }
  def parsed_vehicle_map
    parsed = JSON.parse(vehicle_map.presence || '{}')
    return {} unless parsed.is_a?(Hash)

    # JSON object keys are strings; vehicle ids in the response are
    # integers.
    parsed.transform_keys(&:to_i)
  rescue JSON::ParserError
    {}
  end

  def unassigned_issue_ids
    parsed_response.fetch('unassigned', []).map { |u| u['id'] }
  end

  private

  def validate_planning_range
    return if scheduled_until.nil? || scheduled_on.nil?

    if scheduled_until < scheduled_on
      errors.add(:scheduled_until, :greater_than_start_date)
    elsif planning_days.size > MAX_PLANNING_DAYS
      errors.add(:scheduled_until, :invalid)
    end
  end
end
