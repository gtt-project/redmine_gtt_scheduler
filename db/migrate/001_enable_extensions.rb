class EnableExtensions < ActiveRecord::Migration[5.2]
  def up
    enable_extension :pgrouting
    enable_extension :vrprouting
  end

  def down
    disable_extension :pgrouting
    disable_extension :vrprouting
  end
end
