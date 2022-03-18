module RedmineGttScheduler
  class VrpSolution
    include Redmine::I18n

    def self.call(*_)
      new(*_).call
    end

    def initialize(project)
      @project = project
    end

    def call
      results = ActiveRecord::Base.connection.execute(
        <<-SQL
          SELECT * FROM vrp_vroomPlain(
            $$
            SELECT I.id AS id, geom_to_id(geom) AS location_id
            FROM issues I JOIN trackers T ON(I.tracker_id = T.id) WHERE T.name = '[VRP] Job'
            $$,
            NULL,
            $$
            SELECT
              I.id AS id,
              geom_to_id(ST_StartPoint(geom)) AS p_location_id,
              geom_to_id(ST_EndPoint(geom)) AS d_location_id
              FROM issues I JOIN trackers T ON(I.tracker_id = T.id) WHERE T.name = '[VRP] Shipment'
            $$,
            NULL,
            $$
            SELECT
              I.id AS id,
              geom_to_id(ST_StartPoint(geom)) AS start_id,
              geom_to_id(ST_EndPoint(geom)) AS end_id
              FROM issues I JOIN trackers T ON(I.tracker_id = T.id) WHERE T.name = '[VRP] Service'
            $$,
            NULL,
            NULL,
            $$
            WITH points AS (
              SELECT
                geom_to_id(ST_StartPoint(geom)) AS id,
                ST_StartPoint(geom) AS geom FROM issues I JOIN trackers T
                ON(I.tracker_id = T.id) WHERE T.name IN ('[VRP] Service', '[VRP] Shipment') UNION
              SELECT
                geom_to_id(ST_EndPoint(geom)) AS id,
                ST_EndPoint(geom) AS geom FROM issues I JOIN trackers T
                ON(I.tracker_id = T.id) WHERE T.name IN ('[VRP] Service', '[VRP] Shipment') UNION
              SELECT
                geom_to_id(geom) AS id, geom AS geom FROM issues I
                JOIN trackers T ON(I.tracker_id = T.id) WHERE T.name IN ('[VRP] Job')
            ) SELECT A.id AS start_id, B.id AS end_id, ST_DistanceSphere(A.geom, B.geom)::INTEGER AS duration FROM points A, points B
            $$
          ) WHERE vehicle_id > 0 AND step_type > 1 AND step_type < 6
        SQL
      )

      count = 0

      results.each do |result|
        issue = Issue.find(result['task_id'])
        issue.parent_issue_id = result['vehicle_id']
        issue.save

        # increment the count based on step type (counting a pickup-delivery pair as 1)
        count += 1 if result['step_type'].between?(2, 3)
      end

      count
    end
  end
end
