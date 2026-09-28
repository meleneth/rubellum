require "stringio"

class CellFiles
  MAX_SOURCE_BYTES = 1024 * 1024

  def self.import(notebook:, io:, filename:, format:, expected_revision:)
    raise ArgumentError, "Import format must be markdown, json or csv" unless %w[markdown json csv].include?(format)
    bytes = io.read(MAX_SOURCE_BYTES + 1)
    raise ArgumentError, "Editable source imports are limited to 1 MiB" if bytes.bytesize > MAX_SOURCE_BYTES
    source = bytes.dup.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "Editable source must be UTF-8" unless source.valid_encoding?
    configuration = format == "markdown" ? {} : { "format" => format }
    configuration.merge!("delimiter" => ",", "headers" => true, "skip_blanks" => true) if format == "csv"
    Rubellum::DataCell.parse(source, configuration) unless format == "markdown"
    app = notebook.app
    app.with_lock do
      notebook.with_lock do
        raise History::Conflict, "Notebook changed; reload before importing" unless notebook.head_revision_id == expected_revision
        asset = AssetStorage.upload(app:, io: StringIO.new(bytes), filename:, expected_revision: app.head_revision_id)
        configuration["asset_ids"] = [asset.id]
        History.new(notebook).add_cell(cell_type: format == "markdown" ? "markdown" : "data", source:,
          title: filename, configuration:, expected_notebook_revision: expected_revision)
      end
    end
  end
end
