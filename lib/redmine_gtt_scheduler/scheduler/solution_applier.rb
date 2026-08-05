module RedmineGttScheduler
  module Scheduler
    # Writes a proposed run back to the issues: start/due dates and times
    # via redmine_issue_datetime, assignee from the resource. All-or-
    # nothing inside a transaction; every change is journalized.
    class SolutionApplier
      # warning carries a non-fatal message for a successful apply, for
      # example when some times could not be stored.
      Result = Struct.new(:success, :message, :warning, keyword_init: true) do
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
        Result.new(success: true, warning: times_warning(assignments))
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

      # redmine_issue_datetime ignores the time setters for trackers it is
      # not enabled for. Those issues still get their dates and assignee,
      # but the times are lost, and the dispatcher must be told instead of
      # seeing a clean "applied" message.
      def times_warning(assignments)
        skipped = assignments.filter_map(&:issue)
                             .reject { |issue| RedmineIssueDatetime.enabled_for?(issue.tracker_id) }
        return nil if skipped.empty?

        ids = skipped.map { |issue| "##{issue.id}" }.uniq.join(', ')
        I18n.t(:text_scheduler_times_not_stored, ids: ids)
      end

      def failure(key, options = {})
        Result.new(success: false, message: I18n.t(key, **options))
      end
    end
  end
end
