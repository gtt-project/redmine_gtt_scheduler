module RedmineGttScheduler
  module ProjectExtension
    extend ActiveSupport::Concern

    included do
      has_many :scheduler_resources, dependent: :destroy
      has_many :scheduler_runs, dependent: :destroy
    end
  end
end
