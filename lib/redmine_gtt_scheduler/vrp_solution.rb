module RedmineGttScheduler
  class VrpSolution
    include Redmine::I18n

    def self.call(*_)
      new(*_).call
    end

    def initialize(project)
      @project = project
    end

    def get_trackers()
      trackers = Tracker.all

      trackers.each do |tracker|
        if tracker.name == "[VRP] Job"
          @job_tracker_id = tracker.id
        elsif tracker.name == "[VRP] Shipment"
          @shipment_tracker_id = tracker.id
        elsif tracker.name == "[VRP] Break"
          @break_tracker_id = tracker.id
        elsif tracker.name == "[VRP] Service"
          @service_tracker_id = tracker.id
        end
      end
    end

    def get_priorities()
      @high_priority_id = IssuePriority.where(name: "High").first_or_create.id
      @normal_priority_id = IssuePriority.where(name: "Normal").first_or_create.id
      @low_priority_id = IssuePriority.where(name: "Low").first_or_create.id
    end

    def get_custom_fields()
      @skills_id = CustomField.where(name: "Skills", type: "IssueCustomField").first_or_create.id
      @weight_id = CustomField.where(name: "Weight", type: "IssueCustomField").first_or_create.id
      @volume_id = CustomField.where(name: "Volume", type: "IssueCustomField").first_or_create.id
      @speed_factor_id = CustomField.where(name: "Speed Factor", type: "IssueCustomField").first_or_create.id
      @max_tasks_id = CustomField.where(name: "Max Tasks", type: "IssueCustomField").first_or_create.id
      @vehicle_id = CustomField.where(name: "Vehicle", type: "IssueCustomField").first_or_create.id
    end

    def call
      get_trackers()
      get_priorities()
      # get_custom_fields()

      query = <<-SQL
        SELECT * FROM vrp_vroomPlain(

          -- Jobs SQL
          $JOBS$
          WITH custom_table AS (
            SELECT * FROM crosstab(
              'SELECT customized_id, name, array_agg(CASE WHEN value = $$$$ THEN NULL ELSE value END)
              FROM custom_values CV
              JOIN custom_fields F ON CV.custom_field_id=F.id
              GROUP BY customized_id, name ORDER BY customized_id, name'
            ) AS (id INT, skills TEXT[], volume TEXT[], weight TEXT[])
          )
          SELECT
            I.id AS id,
            geom_to_id(geom) AS location_id,
            CASE WHEN skills = ARRAY[NULL] THEN ARRAY[]::INTEGER[] ELSE skills::INTEGER[] END AS skills,
            ARRAY[volume[1], weight[1]]::INTEGER[] AS delivery,
            CASE
              WHEN I.priority_id = #{@high_priority_id} THEN 3
              WHEN I.priority_id = #{@normal_priority_id} THEN 2
              WHEN I.priority_id = #{@low_priority_id} THEN 1 ELSE 0 END AS priority
            FROM issues I
            JOIN custom_table C ON I.id=C.id
            WHERE
              I.tracker_id = :job_tracker_id AND project_id = :project_id
          $JOBS$,

          -- Jobs Time Windows SQL
          $JOBS_TW$
          SELECT
            I.id AS id,
            CASE WHEN start_date IS NULL THEN 0 ELSE EXTRACT(epoch FROM start_date)::INTEGER END AS tw_open,
            CASE WHEN due_date IS NULL THEN 2147483647 ELSE EXTRACT(epoch FROM due_date)::INTEGER END AS tw_close
            FROM issues I WHERE I.tracker_id = :job_tracker_id AND project_id = :project_id
          $JOBS_TW$,

          -- Shipments SQL
          $SHIPMENTS$
          WITH custom_table AS (
            SELECT * FROM crosstab(
              'SELECT customized_id, name, array_agg(CASE WHEN value = $$$$ THEN NULL ELSE value END)
              FROM custom_values CV
              JOIN custom_fields F ON CV.custom_field_id=F.id
              GROUP BY customized_id, name ORDER BY customized_id, name'
            ) AS (id INT, skills TEXT[], volume TEXT[], weight TEXT[])
          )
          SELECT
            I.id AS id,
            geom_to_id(ST_StartPoint(geom)) AS p_location_id,
            geom_to_id(ST_EndPoint(geom)) AS d_location_id,
            CASE WHEN skills = ARRAY[NULL] THEN ARRAY[]::INTEGER[] ELSE skills::INTEGER[] END AS skills,
            ARRAY[volume[1], weight[1]]::INTEGER[] AS pickup,
            ARRAY[volume[1], weight[1]]::INTEGER[] AS delivery,
            CASE
              WHEN I.priority_id = #{@high_priority_id} THEN 3
              WHEN I.priority_id = #{@normal_priority_id} THEN 2
              WHEN I.priority_id = #{@low_priority_id} THEN 1 ELSE 0 END AS priority
            FROM issues I
            JOIN custom_table C ON I.id=C.id
            WHERE I.tracker_id = :shipment_tracker_id AND project_id = :project_id
          $SHIPMENTS$,

          -- Shipments Time Windows SQL
          $SHIPMENTS_TW$
          SELECT
            I.id AS id, unnest(ARRAY['p', 'd']::CHAR[]) AS kind,
            CASE WHEN start_date IS NULL THEN 0 ELSE EXTRACT(epoch FROM start_date)::INTEGER END AS tw_open,
            CASE WHEN due_date IS NULL THEN 2147483647 ELSE EXTRACT(epoch FROM due_date)::INTEGER END AS tw_close
            FROM issues I WHERE I.tracker_id = :shipment_tracker_id AND project_id = :project_id
          $SHIPMENTS_TW$,

          -- Vehicles SQL
          $VEHICLES$
          WITH custom_table AS (
            SELECT * FROM crosstab(
              'SELECT customized_id, name, array_agg(CASE WHEN value = $$$$ THEN NULL ELSE value END)
              FROM custom_values CV
              JOIN custom_fields F ON CV.custom_field_id=F.id
              GROUP BY customized_id, name ORDER BY customized_id, name'
            ) AS (id INT, max_tasks TEXT[], skills TEXT[], speed_factor TEXT[], vehicle TEXT[], volume TEXT[], weight TEXT[])
          )
          SELECT
            I.id AS id,
            geom_to_id(ST_StartPoint(geom)) AS start_id,
            geom_to_id(ST_EndPoint(geom)) AS end_id,
            CASE WHEN max_tasks = ARRAY[NULL] THEN 2147483647 ELSE max_tasks[1]::INTEGER END AS max_tasks,
            CASE WHEN skills = ARRAY[NULL] THEN ARRAY[]::INTEGER[] ELSE skills::INTEGER[] END AS skills,
            CASE WHEN speed_factor = ARRAY[NULL] THEN 1.0 ELSE speed_factor[1]::FLOAT END AS speed_factor,
            ARRAY[volume[1], weight[1]]::INTEGER[] AS capacity,
            CASE WHEN start_date IS NULL THEN 0 ELSE EXTRACT(epoch FROM start_date)::INTEGER END AS tw_open,
            CASE WHEN due_date IS NULL THEN 2147483647 ELSE EXTRACT(epoch FROM due_date)::INTEGER END AS tw_close
            FROM issues I
            JOIN custom_table C ON I.id=C.id
            WHERE I.tracker_id = :service_tracker_id AND project_id = :project_id
          $VEHICLES$,

          -- Breaks SQL
          NULL,

          -- Breaks Time Windows SQL
          NULL,

          -- Matrix SQL
          $MATRIX$
          WITH points AS (
            SELECT
              geom_to_id(geom) AS id, geom AS geom FROM issues I
              WHERE I.tracker_id IN (:job_tracker_id) AND project_id = :project_id UNION
            SELECT
              geom_to_id(ST_StartPoint(geom)) AS id,
              ST_StartPoint(geom) AS geom FROM issues I
              WHERE I.tracker_id IN (:service_tracker_id, :shipment_tracker_id) AND project_id = :project_id UNION
            SELECT
              geom_to_id(ST_EndPoint(geom)) AS id,
              ST_EndPoint(geom) AS geom FROM issues I
              WHERE I.tracker_id IN (:service_tracker_id, :shipment_tracker_id) AND project_id = :project_id
          ) SELECT A.id AS start_id, B.id AS end_id, ST_DistanceSphere(A.geom, B.geom)::INTEGER AS duration FROM points A, points B
          $MATRIX$

        ) WHERE (vehicle_id > 0 OR vehicle_id = -1) AND task_id > 0
      SQL

      results = ActiveRecord::Base.connection.execute(
        Issue.sanitize_sql_for_assignment([query,
          job_tracker_id: @job_tracker_id,
          shipment_tracker_id: @shipment_tracker_id,
          service_tracker_id: @service_tracker_id,
          project_id: @project.id
        ])
      )

      # display error if results query fail
      if results.nil?
        raise ActiveRecord::StatementInvalid, 'VRP solution query failed'
      end

      count = 0
      unscheduled = 0

      results.each do |result|
        issue = Issue.find(result['task_id'])
        if result['vehicle_id'] != -1
          issue.parent_issue_id = result['vehicle_id']
          issue.save
        end

        # increment the count based on step type (counting a pickup-delivery pair as 1)
        count += 1 if result['step_type'].between?(2, 3) && result['vehicle_id'] > 0
        unscheduled += 1 if result['step_type'].between?(2, 3) && result['vehicle_id'] == -1
      end

      return count, unscheduled
    end
  end
end
