class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  rescue_from History::Conflict, with: :conflict
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, JSON::ParserError, Rubellum::Message::Invalid, with: :invalid_input
  rescue_from Rubellum::BlobStore::Invalid, Rubellum::BlobStore::Full, with: :invalid_input

  private

  def load_notebook
    @app = App.find(params[:app_id])
    @notebook = @app.notebooks.find(params[:notebook_id] || params[:id])
  end

  def conflict(error)
    render plain: "#{error.message}\nYour saved draft has not been removed. Go back to recover it.", status: :conflict
  end

  def invalid_input(error)
    render plain: error.message, status: :unprocessable_content
  end
end
