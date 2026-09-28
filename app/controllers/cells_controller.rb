class CellsController < ApplicationController
  before_action :load_notebook
  before_action :load_cell, except: [:create, :import_file]

  def import_file
    file = params.require(:file)
    raise ArgumentError, "Choose a file to import" unless file.respond_to?(:tempfile)
    CellFiles.import(notebook: @notebook, io: file.tempfile, filename: file.original_filename,
      format: params.require(:format), expected_revision: params.require(:expected_revision))
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def export
    revision = params[:revision] ? @cell.revisions.find(params[:revision]) : @cell.head_revision
    extension = case revision.cell_type
    when "markdown" then "md"
    when "ruby" then "rb"
    when "d3" then "js"
    when "data" then revision.configuration.fetch("format", "json") == "csv" ? "csv" : "json"
    else "json"
    end
    source = revision.cell_type == "table" ? JSON.pretty_generate(revision.configuration) : revision.source
    filename = "#{revision.title.parameterize.presence || revision.cell_type}.#{extension}"
    send_data source, filename:, type: "text/plain; charset=utf-8", disposition: "attachment"
  end

  def preview
    raise ArgumentError, "Draft preview is only available for Markdown cells" unless @cell.head_revision.cell_type == "markdown"
    source = params.fetch(:source, "")
    unless source.is_a?(String) && source.valid_encoding? && source.bytesize <= 1_048_576 && !source.include?("\0")
      raise ArgumentError, "Preview source must be valid UTF-8 Markdown up to 1 MiB"
    end
    AssetReferences.validate!(app_id: @app.id, configuration: {}, source:)
    render html: helpers.markdown(source, app: @app), layout: false
  end

  def create
    type = params.require(:cell_type)
    History.new(@notebook).add_cell(cell_type: type, source: CellTemplates.source(type),
      expected_notebook_revision: params.require(:expected_revision), after: params[:after].presence)
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def update
    ApplicationRecord.transaction do
      revision = History.new(@notebook).save_cell(cell_id: @cell.id, expected_revision: params.require(:expected_revision),
        source: params.fetch(:source, ""), title: params.fetch(:title, ""), cell_type: params.require(:cell_type),
        configuration: JSON.parse(params.fetch(:configuration, "{}")), summary: params.fetch(:summary, ""))
      if params[:intent] == "run"
        ExecutionRequests.submit(notebook: @notebook, cell_id: @cell.id, expected_revision: revision.id,
          inputs: NotebookData.new(@notebook).inputs, datasets: NotebookData.new(@notebook).datasets)
      end
      @cell.drafts.where(editor_id: params[:editor_id]).delete_all if params[:editor_id].present?
    end
    redirect_to app_notebook_path(@app, @notebook, anchor: "cell-#{@cell.id}"), status: :see_other
  end

  def destroy
    History.new(@notebook).remove_cell(cell_id: @cell.id, expected_notebook_revision: params.require(:expected_revision))
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def run
    ExecutionRequests.submit(notebook: @notebook, cell_id: @cell.id, expected_revision: params.require(:expected_revision),
      inputs: NotebookData.new(@notebook).inputs, datasets: NotebookData.new(@notebook).datasets)
    redirect_to app_notebook_path(@app, @notebook, anchor: "cell-#{@cell.id}"), status: :see_other
  end

  def move
    entries = @notebook.head_revision.entries.map { |entry| entry.fetch("cell_id") }
    position = entries.index(@cell.id)
    raise ArgumentError, "cell is not in current document" unless position
    destination = (position + (params[:direction] == "up" ? -1 : 1)).clamp(0, entries.length - 1)
    entries.insert(destination, entries.delete_at(position))
    History.new(@notebook).reorder(cell_ids: entries, expected_notebook_revision: params.require(:expected_revision))
    redirect_to app_notebook_path(@app, @notebook, anchor: "cell-#{@cell.id}"), status: :see_other
  end

  def history
    @revisions = @cell.revisions.order(created_at: :desc)
    @selected = params[:revision] ? @cell.revisions.find(params[:revision]) : @cell.head_revision
  end

  def restore
    History.new(@notebook).restore_cell(cell_id: @cell.id, revision_id: params.require(:revision_id), expected_revision: params.require(:expected_revision))
    redirect_to app_notebook_path(@app, @notebook), status: :see_other
  end

  def output
    render partial: "cells/output", locals: { cell: @cell }
  end

  def draft
    draft = @cell.drafts.find_by(editor_id: params.require(:editor_id))
    render json: draft&.attributes&.slice("source", "title", "cell_type", "configuration", "base_revision_id") || {}
  end

  def save_draft
    editor_id = params.require(:editor_id)
    raise ArgumentError, "invalid editor identity" unless Rubellum::Message::UUID.match?(editor_id)
    draft = @cell.drafts.find_or_initialize_by(editor_id:)
    draft.update!(source: params.fetch(:source, ""), title: params.fetch(:title, ""), cell_type: params.require(:cell_type),
      base_revision_id: params.require(:expected_revision), configuration: JSON.parse(params.fetch(:configuration, "{}")))
    render json: { saved: true }
  end

  def data
    render json: NotebookData.new(@notebook).resolve(@cell.head_revision)
  end

  def parameters
    values = Rubellum::Parameters.new(JSON.parse(@cell.head_revision.source)).values(params.require(:values).permit!.to_h)
    ParameterValue.find_or_initialize_by(cell: @cell).update!(values:)
    render json: { inputs: NotebookData.new(@notebook).inputs }
  end

  private

  def load_cell
    @cell = @notebook.cells.find(params[:id])
  end
end
