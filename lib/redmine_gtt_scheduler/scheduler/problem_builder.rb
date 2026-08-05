module RedmineGttScheduler
  module Scheduler
    # Builds a Scheduler::Problem for one run: open, geolocated issues of
    # the run's project become jobs; active resources become vehicles.
    # All times are anchored on the run's planning day in the reference
    # zone and expressed as epoch seconds.
    class ProblemBuilder
      def initialize(run)
        @run = run
        @zone = RedmineGttScheduler.reference_zone
        date = run.scheduled_on
        @day_start = @zone.local(date.year, date.month, date.day)
        @day_end = @day_start + 1.day
      end

      def build
        excluded = {}
        @skill_ids = skill_id_map
        Problem.new(
          jobs: build_jobs(excluded),
          vehicles: build_vehicles,
          excluded: excluded
        )
      end

      private

      def plannable_issues
        @plannable_issues ||= @run.project.issues.open
                                  .where.not(geom: nil)
                                  .includes(:issue_datetime, :priority, :custom_values)
                                  .to_a
      end

      def build_jobs(excluded)
        plannable_issues.filter_map do |issue|
          build_job(issue, excluded)
        end
      end

      # Solver skill ids for every skill name in play, issues and
      # resources alike. Assigned per problem (sorted names, 1-based), so
      # they are consistent within one request without persisting ids
      # anywhere: renaming a custom field value cannot corrupt stored
      # data, and a name no longer in the vocabulary still matches.
      def skill_id_map
        return {} if RedmineGttScheduler.skills_custom_field.nil?

        names = plannable_issues.flat_map { |issue| issue_skill_names(issue) } |
                resources.flat_map(&:skills)
        names.sort.each_with_index.to_h { |name, index| [name, index + 1] }
      end

      # Required skill names of one issue, from the configured custom
      # field. A multi-value field yields an array, a single-value field
      # a string; both normalize here.
      def issue_skill_names(issue)
        field = RedmineGttScheduler.skills_custom_field
        return [] if field.nil?

        Array(issue.custom_field_value(field)).map(&:to_s).reject(&:blank?)
      end

      def build_job(issue, excluded)
        location = point_of(issue.geom)
        if location.nil?
          excluded[issue.id] = 'unsupported_geometry'
          return nil
        end

        window = time_window_of(issue)
        if window.nil?
          excluded[issue.id] = 'outside_planning_day'
          return nil
        end

        Problem::Job.new(
          id: issue.id,
          location: location,
          service: service_seconds(issue),
          time_window: window,
          priority: priority_of(issue),
          skills: skill_ids_of(issue_skill_names(issue))
        )
      end

      def resources
        @resources ||= @run.resources_for_solving.to_a
      end

      def build_vehicles
        resources.map do |resource|
          Problem::Vehicle.new(
            id: resource.id,
            start: resource.start_location,
            end: resource.end_location,
            time_window: [
              epoch(combine_day(resource.work_starts)),
              epoch(combine_day(resource.work_ends))
            ],
            skills: skill_ids_of(resource.skills)
          )
        end
      end

      # nil rather than [] when there is nothing to say, so the adapter
      # simply omits the key.
      def skill_ids_of(names)
        ids = names.filter_map { |name| @skill_ids[name] }
        ids.empty? ? nil : ids.sort
      end

      def point_of(geom)
        Geometry.point_of(geom)
      end

      # Window from redmine_issue_datetime timestamps when present, from
      # the plain dates otherwise, clamped to the planning day. Returns
      # nil when the window does not intersect the day.
      def time_window_of(issue)
        record = issue.issue_datetime
        open_at = record&.starts_at ||
                  (issue.start_date && @zone.local(issue.start_date.year, issue.start_date.month, issue.start_date.day)) ||
                  @day_start
        close_at = record&.ends_at ||
                   (issue.due_date && @zone.local(issue.due_date.year, issue.due_date.month, issue.due_date.day) + 1.day) ||
                   @day_end

        open_at = [open_at, @day_start].max
        close_at = [close_at, @day_end].min
        return nil if close_at <= open_at

        [epoch(open_at), epoch(close_at)]
      end

      def service_seconds(issue)
        hours = issue.estimated_hours.to_f
        hours.positive? ? (hours * 3600).round : RedmineGttScheduler.default_service_seconds
      end

      # VROOM priorities are 0..100, higher is more important.
      def priority_of(issue)
        position = issue.priority&.position.to_i
        (position * 10).clamp(0, 100)
      end

      def combine_day(time_of_day)
        @day_start + (SchedulerResource.minutes_of_day(time_of_day) || 0).minutes
      end

      def epoch(time)
        time.to_i
      end
    end
  end
end
