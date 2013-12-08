require 'fileutils'
require 'parallel'

def get_edit_link(url)
	uri = URI.parse(url)
	uri.path += '/edit'
	return uri.to_s
end

def strip_quotes(val)
	val = val.strip

	if val[0] == '"' && val[val.length - 1] == '"'
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
	matches = params.scan(/\w+=(?:\w+|"[\w ]+")(?:,(?:\w+|"[\w ]+"))*/)

	return {} if matches.length == 0

	return Hash[*matches.collect {|v| v.split("=") }.flatten]
end

module FormTag
	def form(opts)
		return "<form method=\"GET\" action=\"\">" + opts[:text] + "</form>"
	end
end

class Job
	attr_reader :index

	def initialize(index, piece, procedure)
		@index = index
		@pre_match = piece[:pre_match]
		@procedure = procedure
		@params = piece[:params]
		@query = piece[:query]
	end

	def execute
		@procedure.call(@pre_match, @params, @query).to_s
	end
end

def execute_template(data, &procedure)
	matchable = data

	pieces = []

	until ((match = /<~.+?(?:!!.*?)?~>/.match(matchable)) == nil)
		post_match = match.post_match
		pre_match = match.pre_match

		match = /<~(.+?)(?:!!(.*?))?~>/.match(match[0])

		params = match[1]
		query = match[2]

		pieces << {:pre_match => pre_match, :params => parse_params(params), :query => query}

		matchable = post_match
	end

	jobs = []

	pieces.each_with_index {|piece, index|
		if piece[:params].has_key?('datasource')
			jobs << Job.new(index, piece, procedure)
		else
			piece[:output] = procedure.call(piece[:pre_match], piece[:params], piece[:query])
		end
	}

	Parallel.map(jobs, :in_processes => 30) {|job|
		[job.index, job.execute]
	}.each {|index, output| pieces[index][:output] = output }

	matchable = procedure.call(matchable, {}, "")
	pieces.collect {|piece| piece[:output] }.join + matchable
end

def format_column(col)
	return ("%.2f" % col).to_s if col.is_a? BigDecimal
	return col.to_s
end

def render_table(cols, result)
	view = "<table class='table table-condensed'>"
	view += "<tr>"

	cols.each {|col|
		view += "<th>" + col.to_s + "</th>"
	}

	view += "</tr>"

	result.each {|row|
		view += "<tr>"

		row.each {|col|
			view += "<td>" + format_column(col) + "</td>"
		}

		view += "</tr>"
	}

	view += "</table>"

	return view
end
