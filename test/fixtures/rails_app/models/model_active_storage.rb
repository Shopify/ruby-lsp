class Post < ActiveRecord::Base
  has_one_attached :bar
end
