class ProjectsController < ActionController::Base
  before_action :foo
end

# ignore

before_save :foo
root :bar
