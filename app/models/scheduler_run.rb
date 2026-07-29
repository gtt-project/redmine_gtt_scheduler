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

  validates :scheduled_on, presence: true
  validates :status, inclusion: {in: STATUSES}

  scope :sorted, -> { order(id: :desc) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def discardable?
    proposed? || failed? || draft?
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

  def excluded
    JSON.parse(excluded_issues.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def unassigned_issue_ids
    response = JSON.parse(response_payload.presence || '{}')
    response.fetch('unassigned', []).map { |u| u['id'] }
  rescue JSON::ParserError
    []
  end
end
