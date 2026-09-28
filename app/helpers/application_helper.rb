require "redcarpet"
require "rouge"

module ApplicationHelper
  class MarkdownRenderer < Redcarpet::Render::HTML
    def block_code(code, language)
      lexer = Rouge::Lexer.find_fancy(language || "text", code) || Rouge::Lexers::PlainText
      "<pre class=\"highlight\"><code>#{Rouge::Formatters::HTML.new.format(lexer.lex(code))}</code></pre>"
    end
  end

  def markdown(source, app: nil)
    if app
      ids = source.scan(%r{asset://([0-9a-f-]{36})}).flatten
      available = app.assets.where(id: ids).pluck(:id)
      source = source.gsub(%r{asset://([0-9a-f-]{36})}) { |reference| available.include?(Regexp.last_match(1)) ? app_asset_path(app, Regexp.last_match(1)) : reference }
    end
    renderer = MarkdownRenderer.new(filter_html: true, safe_links_only: true)
    html = Redcarpet::Markdown.new(renderer, tables: true, fenced_code_blocks: true, autolink: true, strikethrough: true).render(source)
    sanitize(html, tags: %w[h1 h2 h3 h4 h5 h6 p br hr ul ol li blockquote pre code span a img table thead tbody tr th td strong em del],
      attributes: %w[href src alt title class])
  end

  def cell_output(cell)
    Execution.joins(:cell_revision).where(cell_revisions: { cell_id: cell.id }).order(created_at: :desc).first
  end
end
