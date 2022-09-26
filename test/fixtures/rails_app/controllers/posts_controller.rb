class ProjectsController < ActionController::Base
  before_action :foo

  def index
    @post = Post.where(active: true).limit(10)
  end

  def show
    @post = Post.find_by(id: params[:id])
  end
end

# ignore

root :bar
