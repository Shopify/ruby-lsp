class Post < ActiveRecord::Base
  belongs_to :foo
  before_save :bar

  has_one_attached :bar
  has_rich_text :content
end

# ignore

resources :foo
before_action :bar

