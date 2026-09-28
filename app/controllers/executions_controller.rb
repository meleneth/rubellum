class ExecutionsController < ApplicationController
  before_action :load_notebook

  def interrupt
    session = NotebookSession.find_by!(notebook: @notebook)
    ExecutionRequests.interrupt(session.executions.find(params[:id]))
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end
end
