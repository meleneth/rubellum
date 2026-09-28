class AssetsController < ApplicationController
  before_action { @app = App.find(params[:app_id]) }

  def index
    @assets = @app.assets.order(created_at: :desc)
  end

  def create
    file = params.require(:file)
    raise ArgumentError, "Choose a file to upload" unless file.respond_to?(:tempfile)
    AssetStorage.upload(app: @app, io: file.tempfile, filename: file.original_filename,
      expected_revision: params.require(:expected_revision))
    redirect_to app_assets_path(@app), status: :see_other
  end

  def show
    asset = @app.assets.find(params[:id])
    bytes = AssetStorage.for_app(@app).read(asset.reference)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'"
    send_data bytes, filename: asset.filename, type: asset.mime_type,
      disposition: asset.image? ? "inline" : "attachment"
  end
end
