# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

scope 'projects/:project_id' do
  resource :schedule_issue, only: %i(show), as: :project_schedule_issues
end
