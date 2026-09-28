class HomeController < ApplicationController
  def index
    @apps = App.includes(:head_revision).order(:created_at)
  end

  def renderer
    render layout: false
  end
end
