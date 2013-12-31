require 'fileutils'
require 'parallel'

def get_edit_link(url)
	uri = URI.parse(url)
	uri.path += '/edit'
	return uri.to_s
end

def strip_quotes(val)
	val = (val || "").to_s.strip

	if (val[0] == '"' && val[val.length - 1] == '"') || (val[0] == '\'' && val[val.length - 1] == '\'')
		return val[1...val.length-1]
	end

	return val
end

def page_exists(page_id)
	File.exists?("#{get_conf['base_files_directory']}/pages/#{page_id}")
end

def load_page(page_id)
	JSON.parse(File.read(get_page_filepath(page_id)))
end

def get_page_filepath(page_id)
	return "#{get_conf['base_files_directory']}/pages/#{page_id}"
end

def write_page(page_id, content)
	if page_id.include?('/') || page_id.include?('..')
		raise "Cannot create a page containing either / or .."
	end

	page_filepath = get_page_filepath(page_id)
	File.open(page_filepath, "w+") {|f| f.write JSON.dump(content) }

	destroy_cache(page_id)
end

def list_of_pages
	Dir.entries("#{get_conf['base_files_directory']}/pages").reject {|file| file.index('.') == 0}
end

def delete_page(page_id)
	destroy_cache(page_id)
	page_filepath = get_page_filepath(page_id)
	File.delete(page_filepath) if File.exists?(page_filepath)
end

def destroy_cache(page_id)
	cache_filepath = "#{get_conf['base_files_directory']}/cache/#{page_id}"
	FileUtils.rm_rf(cache_filepath) if Dir.exists?(cache_filepath)
end

def get_cache_file_name(page_id, params)
	base_path = "#{get_conf['base_files_directory']}/cache/#{page_id}"

	return [base_path, params] if params && params.length > 0
	return [base_path, page_id]
end

def get_cached_page(page_id, params)
	base_path, file_name = get_cache_file_name(page_id, params)

	path = base_path + "/" + file_name

	return [File.mtime(path), File.read(path)] if File.exists?(path)
	return nil
end

def write_cached_page(page_id, params, content)
	base_path, file_name = get_cache_file_name(page_id, params)
	FileUtils.mkdir_p(base_path) if !Dir.exists?(base_path)
	path = base_path + "/" + file_name
	File.open(path, "w+") {|f| f.write(content) }
end

def parse_params(params)
	matches = params.scan(/\w+=(?:\w+|::\w+::|"[\w ]+")(?:,(?:\w+|::\w+::|"[\w ]+"))*/)

	return {} if matches.length == 0

	return Hash[*matches.collect {|v| v.split("=") }.flatten]
end

module FormTag
	def form(opts)
		return "<form method=\"GET\" action=\"\">" + opts[:text] + "</form>"
	end
end

def format_column(col)
	return ("%.2f" % col).to_s if col.is_a? BigDecimal
	return col.to_s
end

def render_table(cols, result, markdown_table_class_added)
	view = ""

	view += "table(table table-compact).\n" if !markdown_table_class_added

	view += "|_." + cols.collect {|col| col.to_s }.join("|_.") + "|\n"

	view += result.collect {|row|
		"|" + row.collect {|col| format_column(col) }.join("|") + "|"
	}.join("\n")

	return view
end

def single_quoted(val)
	"'strip_quotes(val.to_s)'"
end

def double_quoted(val)
	"\"strip_quotes(val.to_s)\""
end

def emit_chart(chart_type, matrix, cols, name, title, xtitle, ytitle, height, width)
	matrix = matrix.clone
	matrix.unshift cols

	if chart_type != :pie
		if xtitle == nil
			return "[xtitle not specified for #{chart_type.to_s} chart.]"
		elsif ytitle == nil
			return "[ytitle not specified for #{chart_type.to_s} chart.]"
		end
	end

	js_object_name = {:line => 'LineChart', :bar => 'BarChart', :pie => 'PieChart'}[chart_type]

	if js_object_name == nil
		return "[Chart type not recognized.]"
	end

	formatted_data = "[" + matrix.collect {|row|
		"[" + row.collect {|val|
			val.is_a?(String) ? "\"#{val}\"" : val.to_s
		}.join(',') + "]"
	}.join(',') + "]"

	width = strip_quotes(width) if width
	height = strip_quotes(height) if height

	options = "var options = {"
	options += " title: '#{title}'," if title
	options += " height: '#{height}'," if height
	options += " width: '#{width}'," if width

	options += "colors: ['#D3D3D3'], vAxis: {title: '#{ytitle}'}, hAxis: {title: '#{xtitle}'}" if [:bar_chart, :line_chart].include?(chart_type)

	options += "};"

	width_clause = width != nil ? "width: #{width}; " : ""
	height_clause = height != nil ? "height: #{height}; " : ""

	name = Random.srand.to_s

	return "<script type=\"text/javascript\">
      google.load(\"visualization\", \"1\", {packages:[\"corechart\"]});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable(#{formatted_data});

        #{options}

        var chart = new google.visualization.#{js_object_name}(document.getElementById('#{name}'));
        chart.draw(data, options);
      } </script> <div id=\"#{name}\" style=\"#{width_clause} #{height_clause}\"></div>"
end
