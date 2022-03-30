class EnableExtensions < ActiveRecord::Migration[5.2]
  def up
    enable_extension :pgrouting unless extensions.include? :pgrouting
    enable_extension :vrprouting unless extensions.include? :vrprouting
    enable_extension :tablefunc unless extensions.include? :tablefunc
  end

  def down
    disable_extension :pgrouting
    disable_extension :vrprouting
  end
end
