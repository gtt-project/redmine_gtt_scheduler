module RedmineGttScheduler
  class ScheduleIssues
    include Redmine::I18n

    def self.call(*_)
      new(*_).call
    end

    def initialize(project)
      @project = project
    end

    def call
      # get the list of issues with tracker "[VRP] Service"
      service_issues = if @project.trackers.where(name: '[VRP] Service').any?
        @project.issues.where(
          'tracker_id = ?',
          Tracker.where(name: '[VRP] Service').first.id
        )
      else
        []
      end

      # get the list of issues with tracker "[VRP] Job"
      job_issues = if @project.trackers.where(name: '[VRP] Job').any?
        @project.issues.where(
          'tracker_id = ?',
          Tracker.where(name: '[VRP] Job').first.id
        )
      else
        []
      end

      # get the list of issues with tracker "[VRP] Shipment"
      shipment_issues = if @project.trackers.where(name: '[VRP] Shipment').any?
        @project.issues.where(
          'tracker_id = ?',
          Tracker.where(name: '[VRP] Shipment').first.id
        )
      else
        []
      end

      # get the list of issues with tracker "[VRP] Break"
      break_issues = if @project.trackers.where(name: '[VRP] Break').any?
        @project.issues.where(
          'tracker_id = ?',
          Tracker.where(name: '[VRP] Break').first.id
        )
      else
        []
      end

      # TEMP: add the job issues as the subtask of service issues
      service_issues.each do |service_issue|
        job_issues.each do |job_issue|
          job_issue.parent_issue_id = service_issue.id
          job_issue.save
        end
      end
    end
  end
end
