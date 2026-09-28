class AppPackagesController < ApplicationController
  def new
  end

  def create
    upload = params.require(:package)
    raise ArgumentError, "Choose a .rubellum-app.tar.gz file" unless upload.respond_to?(:tempfile)
    app = AppPackageImport.call(io: upload.tempfile, as_copy: params[:as_copy] == "true")
    redirect_to app_path(app), status: :see_other
  rescue AppPackageImport::Collision => error
    @error = "#{error.message} Select the file again to import a copy."
    render :new, status: :conflict
  end

  def export
    app = App.find(params[:id])
    mode = params.fetch(:mode, "full")
    bytes = AppPackageExport.call(app:, mode:)
    send_data bytes, filename: "rubellum-#{app.portable_id}-#{mode}.rubellum-app.tar.gz",
      type: "application/gzip", disposition: "attachment"
  end

  def duplicate
    bytes = AppPackageExport.call(app: App.find(params[:id]))
    app = AppPackageImport.call(io: StringIO.new(bytes), as_copy: true)
    redirect_to app_path(app), status: :see_other
  end
end
