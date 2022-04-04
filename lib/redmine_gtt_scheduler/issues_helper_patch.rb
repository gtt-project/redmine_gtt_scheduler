require_dependency 'issues_helper'

module RedmineGttScheduler
  module IssuesHelperPatch
    def self.prepended(base)
      base.module_eval do
        def issue_due_date_details(issue)
          return if issue&.due_date.nil?

          # PATCH: Changed format_date to format_time
          s = format_time(issue.due_date)
          s += " (#{due_date_distance_in_words(issue.due_date)})" unless issue.closed?
          s
        end
      end
    end
  end
end

IssuesHelper.prepend(RedmineGttScheduler::IssuesHelperPatch)
