module RedmineGttScheduler
  module Scheduler
    # Writes a proposed run back to the issues: start/due dates and times
    # via redmine_issue_datetime, assignee from the resource. All-or-
    # nothing inside a transaction; every change is journalized.
    class SolutionApplier
      Result = Struct.new(:success, :message, keyword_init: true) do
        def success?
          success
        end
      end

      def self.call(run, user)
        new(run, user).call
      end

      def initialize(run, user)
        @run = run
        @user = user
        @zone = RedmineGttScheduler.reference_zone
      end

      def call
        return failure(:text_scheduler_not_proposed) unless @run.proposed?

        assignments = @run.scheduler_assignments
                          .includes(:issue, :scheduler_resource)
                          .order(:scheduler_resource_id, :sequence)
        # Applying changes dates, times, and the assignee, so the note-level
        # editable? is not enough; attribute editing is what we need.
        not_editable = assignments.reject { |a| a.issue&.attributes_editable?(@user) }
        if not_editable.any?
          ids = not_editable.map { |a| "##{a.issue_id}" }.join(', ')
          return failure(:text_scheduler_not_editable, ids: ids)
        end

        Issue.transaction do
          assignments.each { |assignment| apply_assignment(assignment) }
          @run.update!(status: SchedulerRun::APPLIED)
        end
        Result.new(success: true)
      rescue ActiveRecord::RecordInvalid => e
        Result.new(success: false, message: e.message)
      end

      private

      def apply_assignment(assignment)
        issue = assignment.issue
        issue.init_journal(@user, I18n.t(:text_scheduler_applied_note, id: @run.id))

        local_start = assignment.starts_at.in_time_zone(@zone)
        local_end = assignment.ends_at.in_time_zone(@zone)
        issue.start_date = local_start.to_date
        issue.due_date = local_end.to_date
        issue.start_time = local_start.strftime('%H:%M')
        issue.due_time = local_end.strftime('%H:%M')

        assignee = assignment.scheduler_resource&.user
        issue.assigned_to = assignee if assignee
        issue.save!
      end

      def failure(key, options = {})
        Result.new(success: false, message: I18n.t(key, **options))
      end
    end
  end
end
