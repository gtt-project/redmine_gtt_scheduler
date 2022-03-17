module RedmineGttScheduler
  class ScheduleIssues
    include Redmine::I18n

    def self.call(*_)
      new(*_).call
    end

    def initialize(project)
      @project = project
    end

    def has_job_tracker?
      @project.trackers.where(name: "[VRP] Job").exists?
    end

    def has_shipment_tracker?
      @project.trackers.where(name: "[VRP] Shipment").exists?
    end

    def has_break_tracker?
      @project.trackers.where(name: "[VRP] Break").exists?
    end

    def has_service_tracker?
      @project.trackers.where(name: "[VRP] Service").exists?
    end

    def call
      # check if all the trackers are present, if not then raise an error
      if !has_job_tracker? || !has_shipment_tracker? || !has_break_tracker? || !has_service_tracker?
        raise "You need to have all the VRP trackers present in the project to use the scheduler."
      end

      service_issues = @project.issues.where(
        'tracker_id = ?',
        Tracker.where(name: '[VRP] Service').first.id
      )

      job_issues = @project.issues.where(
        'tracker_id = ?',
        Tracker.where(name: '[VRP] Job').first.id
      )

      shipment_issues = @project.issues.where(
        'tracker_id = ?',
        Tracker.where(name: '[VRP] Shipment').first.id
      )

      break_issues = @project.issues.where(
        'tracker_id = ?',
        Tracker.where(name: '[VRP] Break').first.id
      )

      # call the method to make call to get the solution for the VRP
      RedmineGttScheduler::VrpSolution.(@project)
    end
  end
end
