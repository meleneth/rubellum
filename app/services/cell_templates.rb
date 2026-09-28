class CellTemplates
  def self.source(type)
    case type
    when "markdown" then "# A new idea\n\nWrite your notes here."
    when "ruby" then "rows = [{\"label\" => \"One\", \"value\" => 12}, {\"label\" => \"Two\", \"value\" => 24}]\nNotebook.emit(\"rows\", data: rows)\nrows"
    when "data" then JSON.pretty_generate([{ "label" => "One", "value" => 12 }, { "label" => "Two", "value" => 24 }])
    when "parameters" then JSON.pretty_generate([{ "name" => "scale", "label" => "Scale", "type" => "slider", "default" => 1, "min" => 0, "max" => 5 }])
    when "table" then ""
    when "d3"
      <<~JS
        async function render({ element, d3, data, inputs, width, height, theme }) {
          const rows = Array.isArray(data) ? data : [];
          const svg = d3.select(element).append("svg").attr("viewBox", [0, 0, width, height]);
          const x = d3.scaleLinear().domain([0, d3.max(rows, d => +d.value) || 1]).range([0, width - 90]);
          const y = d3.scaleBand().domain(rows.map(d => d.label)).range([16, height - 16]).padding(0.2);
          svg.selectAll("rect").data(rows).join("rect")
            .attr("x", 80).attr("y", d => y(d.label)).attr("height", y.bandwidth())
            .attr("width", d => x(+d.value) * (inputs.scale ?? 1)).attr("fill", theme.accent)
            .append("title").text(d => `${d.label}: ${d.value}`);
          svg.selectAll("text").data(rows).join("text").attr("x", 4)
            .attr("y", d => y(d.label) + y.bandwidth() / 2).attr("fill", theme.foreground).text(d => d.label);
          return () => svg.remove();
        }
      JS
    else raise ArgumentError, "Unknown cell type"
    end
  end
end
