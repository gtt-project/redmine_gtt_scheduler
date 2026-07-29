module RedmineGttScheduler
  module Scheduler
    # Explains why issues came back unassigned.
    #
    # VROOM does not say why: an unassigned entry carries only id, type and the
    # echoed description/location. So the reasons here are derived locally by
    # re-examining the same problem the run was solved from, and the UI labels
    # them as such rather than pretending the solver reported them.
    class UnassignedReport
      OUTSIDE_WORKING_HOURS = :outside_working_hours
      LONGER_THAN_SHIFT = :service_longer_than_shift
      NO_ROOM = :no_room_in_plan
      UNKNOWN = :unknown

      def self.call(run)
        new(run).call
      end

      def initialize(run)
        @run = run
      end

      # => { issue_id => reason symbol }
      def call
        ids = @run.unassigned_issue_ids
        return {} if ids.empty?

        problem = ProblemBuilder.new(@run).build
        jobs = problem.jobs.index_by(&:id)
        windows = problem.vehicles.map(&:time_window).compact
        ids.each_with_object({}) do |id, out|
          out[id] = reason_for(jobs[id], windows)
        end
      end

      private

      def reason_for(job, windows)
        return UNKNOWN if job.nil? || windows.empty?

        open_at, close_at = job.time_window
        return UNKNOWN if open_at.nil? || close_at.nil?

        overlapping = windows.select { |from, to| from < close_at && to > open_at }
        return OUTSIDE_WORKING_HOURS if overlapping.empty?

        longest = overlapping.map { |from, to| to - from }.max
        return LONGER_THAN_SHIFT if job.service.to_i > longest

        NO_ROOM
      end
    end
  end
end
