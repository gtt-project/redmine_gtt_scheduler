class AddSkillsToSchedulerResources < ActiveRecord::Migration[7.2]
  def change
    # JSON array of skill names, from the vocabulary of the configured
    # issue custom field. Stored as names, not ids: ids are assigned per
    # solver request, so renaming custom field values cannot corrupt
    # stored resources.
    #
    # Nullable on purpose: Rails' serialize stores the empty default as
    # NULL, and the JSON coder loads NULL back as [].
    add_column :scheduler_resources, :skills, :text
  end
end
