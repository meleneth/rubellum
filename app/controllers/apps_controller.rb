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
    app.with_lock do
      raise History::Conflict, "App metadata changed" unless app.head_revision_id == params[:expected_revision]
      current = app.head_revision
      revision = app.revisions.create!(parent_id: current.id, title: params.fetch(:title, current.title),
        description: params.fetch(:description, current.description), configuration: current.configuration,
        landing_notebook_id: params.fetch(:landing_notebook_id, current.landing_notebook_id), summary: "Update app metadata")
      app.update!(head_revision: revision, archived_at: params[:archived] == "true" ? Time.current : nil)
    end
    redirect_to root_path, status: :see_other
  end
end
