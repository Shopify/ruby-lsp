class PostJob < ApplicationJob
  queue_as :default

  def perform(*guests)
    # Do something later
  end
end

# ignore

before_save :foo
before_action :bar

