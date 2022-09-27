class PostJob < ApplicationJob
  queue_as :default

  def perform(id)
    # Do something later
  end
end

# ignore

before_action :bar

