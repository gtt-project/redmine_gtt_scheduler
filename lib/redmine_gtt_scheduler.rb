require_relative 'redmine_gtt_scheduler/project_extension'
require_relative 'redmine_gtt_scheduler/scheduler/problem'
require_relative 'redmine_gtt_scheduler/scheduler/solution'
require_relative 'redmine_gtt_scheduler/scheduler/adapter'
require_relative 'redmine_gtt_scheduler/scheduler/vroom_express_adapter'
require_relative 'redmine_gtt_scheduler/scheduler/problem_builder'
require_relative 'redmine_gtt_scheduler/scheduler/solver'
require_relative 'redmine_gtt_scheduler/scheduler/solution_applier'

module RedmineGttScheduler
  class MissingDependencyError < StandardError; end

  def self.setup
    Project.include(ProjectExtension) unless Project.include?(ProjectExtension)
  end

  def self.settings
    Setting.plugin_redmine_gtt_scheduler
  end

  def self.vroom_url
    settings['vroom_url'].presence || 'http://localhost:3000'
  end

  def self.default_service_seconds
    minutes = settings['default_service_minutes'].to_i
    (minutes.positive? ? minutes : 30) * 60
  end

  def self.solver_timeout
    seconds = settings['solver_timeout'].to_i
    seconds.positive? ? seconds : 60
  end

  # All schedule times are anchored in the same reference zone that
  # redmine_issue_datetime uses for its date mirror. That plugin is a hard
  # dependency, so say so clearly instead of raising NameError deep in a
  # helper when it is missing.
  def self.reference_zone
    unless defined?(RedmineIssueDatetime)
      raise MissingDependencyError,
            'redmine_gtt_scheduler requires the redmine_issue_datetime plugin ' \
            '(https://github.com/gtt-project/redmine_issue_datetime)'
    end

    RedmineIssueDatetime.reference_zone
  end
end
