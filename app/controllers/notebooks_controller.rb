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
    @notebook.with_lock do
      @notebook.head_revision.ordered_revisions.select { |revision| revision.cell_type == "ruby" }.each do |revision|
        ExecutionRequests.submit(notebook: @notebook, cell_id: revision.cell_id, expected_revision: revision.id,
          inputs: NotebookData.new(@notebook).inputs, datasets: NotebookData.new(@notebook).datasets)
      end
    end
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end
end
