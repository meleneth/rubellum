class NotebooksController < ApplicationController
  before_action :load_notebook, except: :create

  def create
    app = App.find(params[:app_id])
    notebook = History.create_notebook(app:, title: params.require(:title))
    redirect_to app_notebook_path(app, notebook), status: :see_other
  end

  def show
    @revision = params[:revision] ? @notebook.revisions.find(params[:revision]) : @notebook.head_revision
    @historical = @revision.id != @notebook.head_revision_id
    @cells = @revision.ordered_revisions
    @session = NotebookSession.find_by(notebook: @notebook)
  end

  def update
    History.new(@notebook).update_notebook(title: params.require(:title), description: params.fetch(:description, ""),
      expected_notebook_revision: params.require(:expected_revision), summary: params.fetch(:summary, "Update notebook metadata"))
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def history
    @revisions = @notebook.revisions.order(created_at: :desc)
  end

  def restore
    History.new(@notebook).restore_notebook(revision_id: params.require(:revision_id), expected_notebook_revision: params.require(:expected_revision))
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def reset
    session = NotebookSession.find_by!(notebook: @notebook)
    ExecutionRequests.reset(session)
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def run_all
    RunAll.call(@notebook)
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def restart_all
    ExecutionRequests.restart_all(@notebook)
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end
end
