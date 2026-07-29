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

  validates :scheduled_on, presence: true
  validates :status, inclusion: {in: STATUSES}

  scope :sorted, -> { order(id: :desc) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def discardable?
    proposed? || failed? || draft?
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
