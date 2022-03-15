class ScheduleIssuesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def show
    flash[:notice] = "Scheduled the issues"
    # call the lib/redmine_gtt_scheduler/schedule_issues.rb method to schedule the issues
    RedmineGttScheduler::ScheduleIssues.(@project)
    redirect_to :back
  end

  private

  def find_project_by_project_id
    @project = Project.find params[:project_id]
  end

  def authorize
    if User.current.allowed_to?(:manage_members, @project, global: false)
      true
    else
      if @project && @project.archived?
        render_403 :message => :notice_not_authorized_archived_project
      else
        deny_access
      end
    end
  end
end
