require 'fileutils'
require 'parallel'
require 'sqlite3'
require 'sequel'

def page
	return SQLiteStore.new
end

class SQLiteStore
	attr_reader :version

	def initialize
		@version = get_version
	end

	def db_file_path
		get_base_path("data.sqlite")
	end

	def db_exists
		File.exists?(db_file_path)
	end

	def db
		return @db if @db != nil

		@db = Sequel.sqlite(db_file_path)
		return @db
	end

	def get_version
		 return db[:version].get(:version).to_i if db.table_exists?(:version)
		 return -1
	end

	def get_base_path(file_path)
		return get_conf['base_files_directory'] + "/#{file_path}"
	end

	def update_database_version(version)
		db[:version].update(:version => version)
	end

	def migrate
		if @version == -1
			db.create_table(:version) do
				Bignum :version
			end

			db.create_table(:pages) do
				primary_key :id, type: Bignum
				String :page_id, unique: true
				Text :title
				Text :content
			end

			db[:version].insert(0)

			FlatFileStore.new.list.each {|id|
				data = FlatFileStore.new.load(id)
				title = data['title']
				content = data['content']

				db[:pages].insert(page_id: id, title: title, content: content)
			}

			db.run 'PRAGMA journal_mode=WAL'
		end
	end

	def close
		if @db
			@db.disconnect
			@db = nil
		end
	end

	def load(page_id)
		page = db[:pages].where(page_id: page_id).first
		if page then to_hash(page) else nil end
	end

	def save(page_id, content)
		existing_page = load(page_id)

		if existing_page != nil
			db[:pages].where(page_id: page_id).update(title: content['title'], content: content['content'])
		else
			db[:pages].where(page_id: page_id).insert(page_id: page_id, title: content['title'], content: content['content'])
		end

		destroy_cache(page_id)
	end

	def to_hash(page)
		return {
			'title' => page[:title],
			'page_id' => page[:page_id],
			'content' => page[:content]
		}
	end

	def list
		db[:pages].collect {|page| {page_id: page[:page_id], title: page[:title] } }.sort {|page1, page2| page1[:title] <=> page2[:title] }
	end

	def delete(page_id)
		destroy_cache(page_id)
		db[:pages].where(page_id: page_id).delete
	end
end

class FlatFileStore
	def exists?(page_id)
		File.exists?("#{get_conf['base_files_directory']}/pages/#{page_id}")
	end

	def load(page_id)
		JSON.parse(File.read(get_page_filepath(page_id)))
	end

	def get_page_filepath(page_id)
		return "#{get_conf['base_files_directory']}/pages/#{page_id}"
	end

	def save(page_id, content)
		if page_id.include?('/') || page_id.include?('..')
			raise "Cannot create a page containing either / or .."
		end

		page_filepath = get_page_filepath(page_id)
		File.open(page_filepath, "w+") {|f| f.write JSON.dump(content) }

		destroy_cache(page_id)
	end

	def list
		Dir.entries("#{get_conf['base_files_directory']}/pages").reject {|file| file.index('.') == 0}
	end

	def delete(page_id)
		destroy_cache(page_id)
		page_filepath = get_page_filepath(page_id)
		File.delete(page_filepath) if File.exists?(page_filepath)
	end
end

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
		return "<form method=\"GET\" action=\"\">" + opts[:text] + " <input type='submit' value='Query'> </form>"
	end
end

def decimal_format(col)
	return ("%.2f" % col).to_s if col.is_a? BigDecimal
	return col.to_s
end

def conditional_col_format(col_name, value, original_value, rules)
	return "|#{value.to_s}" if rules == nil || rules.length == 0

	column_start = "|"
	column_styles = []
	column_value = value.to_s

	rules.each {|rule|
		failed = false
		name_found = false

		rule[:conditions].each {|condition|
			test_col_name = condition[:column].to_s
			next if test_col_name != col_name
			name_found = true

			test_value = condition[:value]

			if original_value.class == String
				test_value = test_value.to_s
			elsif original_value.is_a?(Numeric)
				if original_value.class == Integer
					test_value = test_value.to_i
				else
					test_value = BigDecimal.new(test_value)
				end
			else
				return "Conditional formatting does not recognize this value type."
			end

			if condition[:operator] != nil then
				case condition[:operator].to_s
				when '>'
					failed = !(value.to_i > test_value.to_i)
				when '>='
					failed = !(value.to_i >= test_value.to_i)
				when '='
					failed = !(value.to_i == test_value.to_i)
				when '<'
					failed = !(value.to_i < test_value.to_i)
				when '<='
					failed = !(value.to_i <= test_value.to_i)
				when '!='
					failed = !(value.to_s != test_value.to_s)
				when 'gt'
					failed = !(value.to_s > test_value.to_s)
				when 'ge'
					failed = !(value.to_s >= test_value.to_s)
				when 'lt'
					failed = !(value.to_s < test_value.to_s)
				when 'le'
					failed = !(value.to_s <= test_value.to_s)
				when 'eq'
					failed = !(value.to_s == test_value.to_s)
				else
					failed = true
				end
			end
		}

		if !failed && name_found
			rule[:format].each {|style|
				style = strip_quotes(style.to_s)
				
				case style
				when 'bold'
					column_value = "*#{column_value}*"
				when 'italics'
					column_value = "_#{column_value}_"
				when 'underline'
					column_value = "+#{column_value}+"
				else
					style_type, style_value = style.split(':', 2)

					case style_type
					when 'text'
						column_value = "%{color:#{style_value}}#{column_value}%"
					when 'background', 'bg'
						column_styles << "background-color: #{style_value}"
					when 'format'
						style_value = strip_quotes(style_value)
						prepend = style_value.index('%%') == 0
						append = style_value.reverse.index('%%') == 0

						original_value = column_value
						column_value = style_value.split('%%').join(column_value)
						column_value += original_value if append
						column_value = original_value + column_value if prepend
					end
				end
					
			}
		end
	}

	column_style = column_styles.length > 0 ? "{#{column_styles.join(';')}}." : ''

	return "#{column_start}#{column_style} #{column_value}"
end

def render_table(cols, result, markdown_table_class_added, conditional_formatting_rules)
	view = ""

	view += "table(table table-compact).\n" if !markdown_table_class_added

	view += "|_." + cols.collect {|col| col.to_s }.join("|_.") + "|\n"

	conditional_formatting_rules = [conditional_formatting_rules] if !conditional_formatting_rules.is_a?(Array)

	view += result.collect {|row|
		cols.zip(row).collect {|col_name, value| conditional_col_format(col_name, decimal_format(value), value, conditional_formatting_rules) }.join + "|"
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

	xtitle = xtitle || ""
	ytitle = ytitle || ""

	xtitle = strip_quotes(xtitle)
	ytitle = strip_quotes(ytitle)

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

	options += "colors: ['#D3D3D3'], vAxis: {title: '#{ytitle}'}, hAxis: {title: '#{xtitle}'}" if [:bar, :line].include?(chart_type)

	options += "};"

	width_clause = width != nil ? "width: #{width}; " : ""
	height_clause = height != nil ? "height: #{height}; " : ""

	name = (Random.new.rand * 100000).to_i.to_s

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

store = SQLiteStore.new

if store.version == -1
	store.migrate
end

store.close
store = nil
