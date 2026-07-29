RedmineApp::Application.routes.draw do
  scope 'projects/:project_id' do
    resources :scheduler_runs, only: [:index, :show, :new, :create], as: :project_scheduler_runs do
      member do
        post 'apply'
        post 'discard'
      end
    end
    resources :scheduler_resources, except: [:show], as: :project_scheduler_resources
  end
end
