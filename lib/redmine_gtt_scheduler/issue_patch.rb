require_dependency 'issue'

module RedmineGttScheduler
  module IssuePatch
    def self.included(base)
      base.class_eval do
        self.validators_on(:start_date).each { |val| val.attributes.delete(:start_date) }
        self.validators_on(:due_date).each { |val| val.attributes.delete(:due_date) }

        # change validator of start_date to validate for datetime instead of date
        validates :start_date, :date_time => true
        validates :due_date, :date_time => true
      end
    end
  end
end

Issue.send(:include, RedmineGttScheduler::IssuePatch)
