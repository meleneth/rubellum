class AppsController < ApplicationController
  def create
    app = History.create_app(title: params.require(:title))
    notebook = History.create_notebook(app:, title: "Welcome")
    redirect_to app_notebook_path(app, notebook), status: :see_other
  end

  def show
    app = App.find(params[:id])
    notebook = app.notebooks.find_by(id: app.head_revision.landing_notebook_id) || app.notebooks.first
    redirect_to notebook ? app_notebook_path(app, notebook) : root_path
  end

  def update
    app = App.find(params[:id])
    archived = nil
    if params.key?(:archived)
      raise ArgumentError, "Invalid archive state" unless %w[true false].include?(params[:archived])
      archived = params[:archived] == "true"
    end
    AppHistory.new(app).update(expected_revision: params.require(:expected_revision),
      attributes: params.permit(:title, :description, :landing_notebook_id).to_h, archived:,
      summary: params.fetch(:summary, "Update app metadata"))
    redirect_to root_path, status: :see_other
  end

  def history
    @app = App.find(params[:id])
    @revisions = @app.revisions.order(created_at: :desc, id: :desc)
    @selected = params[:revision] ? @app.revisions.find(params[:revision]) : @app.head_revision
  end

  def restore
    app = App.find(params[:id])
    AppHistory.new(app).restore(revision_id: params.require(:revision_id), expected_revision: params.require(:expected_revision))
    redirect_to history_app_path(app), status: :see_other
  end
end
