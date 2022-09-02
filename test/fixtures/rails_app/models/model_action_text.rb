class Post < ActiveRecord::Base
  has_rich_text :content
end
