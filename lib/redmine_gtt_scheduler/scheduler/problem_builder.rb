module RedmineGttScheduler
  module Scheduler
    # Builds a Scheduler::Problem for one run: open, geolocated issues of
    # the run's project become jobs; active resources become vehicles,
    # one per resource and working day of the planning range. All times
    # are anchored in the reference zone and expressed as epoch seconds.
    class ProblemBuilder
      def initialize(run)
        @run = run
        @zone = RedmineGttScheduler.reference_zone
        # Looked up once per build: both accessors hit the database, and
        # they are consulted for every issue.
        @skills_field = RedmineGttScheduler.skills_custom_field
        @capacity_field = RedmineGttScheduler.capacity_custom_field
        @days = run.planning_days
        @range_start = day_start(@days.first)
        @range_end = day_start(@days.last) + 1.day
      end

      def build
        excluded = {}
        @skill_ids = skill_id_map
        @capacity_active = capacity_active?
        vehicles, vehicle_index = build_vehicles
        Problem.new(
          jobs: build_jobs(excluded),
          vehicles: vehicles,
          excluded: excluded,
          vehicle_index: vehicle_index
        )
      end

      private

      def plannable_issues
        @plannable_issues ||= begin
          scope = @run.project.issues.open
                      .where.not(geom: nil)
                      .includes(:issue_datetime, :priority)
          # Custom values are only read by the skills and capacity
          # features, so only preload them when one is on.
          scope = scope.includes(:custom_values) if @skills_field || @capacity_field
          scope.to_a
        end
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
        return {} if @skills_field.nil?

        names = plannable_issues.flat_map { |issue| issue_skill_names(issue) } |
                resources.flat_map(&:skills)
        names.sort.each_with_index.to_h { |name, index| [name, index + 1] }
      end

      # Required skill names of one issue, from the configured custom
      # field. A multi-value field yields an array, a single-value field
      # a string; both normalize here.
      def issue_skill_names(issue)
        return [] if @skills_field.nil?

        Array(issue.custom_field_value(@skills_field)).map(&:to_s).reject(&:blank?)
      end

      def build_job(issue, excluded)
        location = point_of(issue.geom)
        if location.nil?
          excluded[issue.id] = 'unsupported_geometry'
          return nil
        end

        window = time_window_of(issue)
        if window.nil?
          excluded[issue.id] = @days.size > 1 ? 'outside_planning_range' : 'outside_planning_day'
          return nil
        end

        Problem::Job.new(
          id: issue.id,
          location: location,
          service: service_seconds(issue),
          time_window: window,
          priority: priority_of(issue),
          skills: skill_ids_of(issue_skill_names(issue)),
          delivery: (@capacity_active ? [load_of(issue)] : nil)
        )
      end

      # The capacity dimension is only emitted when the field is set and
      # at least one issue actually carries load: an all-zero dimension
      # would constrain nothing, and the solver requires every job and
      # vehicle to carry it once any does.
      def capacity_active?
        @capacity_field.present? &&
          plannable_issues.any? { |issue| load_of(issue).positive? }
      end

      def load_of(issue)
        return 0 if @capacity_field.nil?

        [issue.custom_field_value(@capacity_field).to_i, 0].max
      end

      # An unlimited resource still needs a number the solver accepts, so
      # it gets the total load of all jobs, which no route can exceed.
      def unlimited_capacity
        @unlimited_capacity ||= [plannable_issues.sum { |issue| load_of(issue) }, 1].max
      end

      # The model validates capacity >= 0, but a value written past the
      # validations must still not reach the solver as a negative.
      def capacity_of(resource)
        resource.capacity ? [resource.capacity, 0].max : unlimited_capacity
      end

      def resources
        @resources ||= @run.resources_for_solving.to_a
      end

      # One vehicle per resource per working day. Single-day runs keep
      # vehicle id == resource id (and an empty index), so their stored
      # payloads read exactly as before multi-day planning existed;
      # multi-day runs use synthetic sequential ids and report the
      # mapping in the returned index.
      def build_vehicles
        multi_day = @days.size > 1
        vehicles = []
        index = {}
        resources.each do |resource|
          @days.each do |day|
            next unless resource.works_on?(day)

            id = multi_day ? vehicles.size + 1 : resource.id
            index[id] = [resource.id, day] if multi_day
            vehicles << build_vehicle(id, resource, day)
          end
        end
        [vehicles, index]
      end

      def build_vehicle(id, resource, day)
        start_of_day = day_start(day)
        Problem::Vehicle.new(
          id: id,
          start: resource.start_location,
          end: resource.end_location,
          time_window: [
            epoch(work_time(start_of_day, resource.work_starts)),
            epoch(work_time(start_of_day, resource.work_ends))
          ],
          skills: skill_ids_of(resource.skills),
          capacity: (@capacity_active ? [capacity_of(resource)] : nil)
        )
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
      # the plain dates otherwise, clamped to the planning range. Returns
      # nil when the window does not intersect the range.
      def time_window_of(issue)
        record = issue.issue_datetime
        open_at = record&.starts_at ||
                  (issue.start_date && day_start(issue.start_date)) ||
                  @range_start
        close_at = record&.ends_at ||
                   (issue.due_date && day_start(issue.due_date) + 1.day) ||
                   @range_end

        open_at = [open_at, @range_start].max
        close_at = [close_at, @range_end].min
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

      def day_start(date)
        @zone.local(date.year, date.month, date.day)
      end

      def work_time(start_of_day, time_of_day)
        start_of_day + (SchedulerResource.minutes_of_day(time_of_day) || 0).minutes
      end

      def epoch(time)
        time.to_i
      end
    end
  end
end
