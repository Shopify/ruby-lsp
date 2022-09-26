class PostJob < ApplicationJob
  queue_as :default

  def perform(id)
    post = Post.find(id)
    # Do something later
  end
end

# ignore

before_action :bar

