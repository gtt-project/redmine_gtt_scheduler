module RedmineDatetimeCustomField
  class Hooks < Redmine::Hook::ViewListener

    # Convert time to local time without changing the value
    def convert_time_to_local(time)
      return nil unless time
      user = User.current
      options = {}
      options[:format] = (Setting.time_format.blank? ? :time : Setting.time_format)
      time = time.to_time if time.is_a?(String)

      if user.time_zone
        time.asctime.in_time_zone(user.time_zone)
      else
        time.utc? ? time.localtime : time
      end
    end

    # Fix the issue start_date and due_date to be local time
    def fix_issue_date(issue)
      return nil unless issue
      issue.start_date = convert_time_to_local(issue.start_date)
      issue.due_date = convert_time_to_local(issue.due_date)
      issue
    end

    def controller_issues_new_before_save(context)
      context[:issue] = fix_issue_date(context[:issue])
    end

    def controller_issues_bulk_edit_before_save(context)
      context[:issue] = fix_issue_date(context[:issue])
    end

    def controller_issues_edit_before_save(context)
      context[:issue] = fix_issue_date(context[:issue])
    end

  end
end
