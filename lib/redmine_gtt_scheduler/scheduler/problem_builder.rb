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
        Problem.new(
          jobs: build_jobs(excluded),
          vehicles: build_vehicles,
          excluded: excluded
        )
      end

      private

      def build_jobs(excluded)
        issues = @run.project.issues.open
                     .where.not(geom: nil)
                     .includes(:issue_datetime, :priority)
        issues.filter_map do |issue|
          build_job(issue, excluded)
        end
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
          priority: priority_of(issue)
        )
      end

      def build_vehicles
        @run.project.scheduler_resources.active.map do |resource|
          Problem::Vehicle.new(
            id: resource.id,
            start: resource.start_location,
            end: resource.end_location,
            time_window: [
              epoch(combine_day(resource.work_starts)),
              epoch(combine_day(resource.work_ends))
            ]
          )
        end
      end

      # [lon, lat] for points; other geometries use their centroid when
      # available, otherwise the issue is excluded.
      def point_of(geom)
        return nil if geom.nil?
        return [geom.x, geom.y] if geom.geometry_type == RGeo::Feature::Point

        centroid = geom.respond_to?(:centroid) ? geom.centroid : nil
        centroid && [centroid.x, centroid.y]
      rescue RGeo::Error::RGeoError, RGeo::Error::UnsupportedOperation
        nil
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
        hour, minute = time_of_day.to_s.split(':').map(&:to_i)
        @day_start + hour.to_i.hours + minute.to_i.minutes
      end

      def epoch(time)
        time.to_i
      end
    end
  end
end
