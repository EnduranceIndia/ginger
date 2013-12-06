require 'json'
require 'uri'

require './libs/params'
require './config'

require './libs/page_utils'
require './libs/database'

require 'rubygems'
require 'sinatra'
require 'redcloth'

base_files_directory = get_conf['base_files_directory']

stored_data = {
	:request_params => {
	},
	:user_variables => {
	}
}

def add_cache_request(url)
	return if url.index('cache=true') != nil
	return url + '&cache=true' if url.index('?') != nil
	return url + '?cache=true'
end

def remove_cache_request(url, cache_switch)
	return "" if url == nil
	clean_url = url.gsub(/&cache=#{cache_switch}/, "")
	clean_url = clean_url.gsub(/\?cache=#{cache_switch}/, "")
	clean_url = clean_url.gsub(/cache=#{cache_switch}/, "") if clean_url.index("cache=#{cache_switch}") == 0
	clean_url = clean_url.gsub(/\?\s*$/, "")

	return clean_url
end

def emit_chart(chart_type, matrix, cols, name, title, xtitle, ytitle, height, width)
	matrix = matrix.clone
	matrix.unshift cols

	if name == nil
		return "[name not specified for #{chart_type.to_s} chart.]"
	elsif xtitle == nil
		return "[xtitle not specified for #{chart_type.to_s} chart.]"
	elsif ytitle == nil
		return "[ytitle not specified for #{chart_type.to_s} chart.]"
	end

	js_object_name = {:line_chart => 'LineChart', :bar_chart => 'BarChart', :pie_chart => 'PieChart'}[chart_type]

	if js_object_name == nil
		return "[Chart type not recognized.]"
	end

	formatted_data = "[" + matrix.collect {|row|
		"[" + row.collect {|val|
			val.is_a?(String) ? "\"#{val}\"" : val.to_s
		}.join(',') + "]"
	}.join(',') + "]"

	options = "var options = {"
	options += " title: #{title}," if title
	options += " height: #{height}," if height
	options += " width: #{width}," if width

	options += "colors: ['#D3D3D3'], vAxis: {title: #{ytitle}}, hAxis: {title: #{xtitle}}" if [:bar_chart, :line_chart].include?(chart_type)

	options += "};"

	width_clause = width != nil ? "width: #{width}; " : ""
	height_clause = height != nil ? "height: #{height}; " : ""


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

def format(connection, value, type)
	return "#{connection.escape(value)}" if type == 'string'
	return value
end

def get_query_from_template(connection, query, request_params)
	matchable = query
	new_data = ""

	until ((match = /<([ .\w]+) *= *::(\w+)::>/.match(matchable)) == nil)
		post_match = match.post_match
		pre_match = match.pre_match

		pre_equal = match[1]
		param_name = match[2]

		if request_params.has_key?(param_name)
			value = request_params[param_name][:value]
			type = request_params[param_name][:type]

			value = format(connection, value, type)

			new_data += pre_match + " " + pre_equal + "=" + value
		else
			new_data += pre_match
		end

		matchable = post_match
	end

	return new_data + matchable
end

get '/' do
	@list_of_pages = list_of_pages
	haml :page_list
end

get '/page/:page_id/edit' do
	@page_id = params[:page_id]
	@page = nil

	if page_exists(@page_id)
		@page = load_page(@page_id)
	end

	haml :edit_page
end

get '/page/:page_id' do
	@page_id = params[:page_id]

	if page_exists(@page_id)
		@page = load_page(@page_id)

		uri = URI.parse(request.url)

		query_params = remove_cache_request(uri.query, true) || ""
		last_modified_time, cached_page = get_cached_page(@page_id, query_params)

		if params['cache'] != 'true' && cached_page
			@page['content'] = cached_page
			cached_time = Time.now - last_modified_time

			minute = 60
			hour = 60 * minute
			day = 24 * hour

			if cached_time / minute < 2
				@cached_time = "#{cached_time.round} seconds"
			elsif cached_time / hour < 2
				@cached_time = "#{(cached_time / minute).round} minutes"
			elsif cached_time / day < 2
				@cached_timecached_time = "#{(cached_time / hour).round} hours"
			else
				@cached_timecached_time = "#{(cached_time / day).round} days"
			end

			@cached_time = "This page was cached #{@cached_time} ago."
		else
			@page['content'] = execute_template(@page['content']) {|template_params, query|
				if template_params['display'] == 'panel'
					"table{float:left; margin-right:10px; margin-bottom: 10px}."
				elsif template_params['display'] == 'panel_end'
					"<div style='clear: both;'></div>"
				elsif template_params.has_key?('input')
					if template_params['input'] == 'dropdown'
						if !template_params.has_key?('name')
							"[No name specified for input field.]"
						elsif !template_params.has_key?('type')
							"[No type specified for input field.]"
						elsif !template_params.has_key?('title')
							"[No title specified for input field.]"
						elsif !template_params.has_key?('options')
							"[No options have been specified for input #{template_params['name']}.]"
						elsif !template_params.has_key?('ids')
							"[No ids have been specified for input #{template_params['name']}.]"
						else
							options = template_params['options'].split(',')
							ids = template_params['ids'].split(',')

							if options.length != ids.length
								"[Options and ids of input #{template_params['name']} are not of equal length.]"
							else
								name = strip_quotes(template_params['name'])
								title = strip_quotes(template_params['title'])
								type = template_params['type']

								param_name = "param_#{name}"
								if params.has_key?(param_name) && params[param_name].length > 0
									stored_data[:request_params][name] = {:value => params[param_name], :type => type}
								end

								html = "<span><select name=param_#{name}><option value=''>[#{title}]</option>"

								options.zip(ids).each {|option, id|
									option = strip_quotes(option)
									selected_state = params["param_#{name}"] == id ? "selected=true" : ""
									html += "<option value='#{id}' #{selected_state}>#{option}</option>"
								}

								html += "</select></span>"

								html
							end
						end
					elsif template_params['input'] == 'submit'
						"<input type=\"submit\" value=\"Query\"></input>"
					end
				elsif template_params.has_key?('store')
					value = nil
					error = nil

					if template_params.has_key?('case')
						if !template_params.has_key?('options')
							"[options have not been specified for case statement.]"
						elsif !template_params.has_key?('values')
							"[values have not been specified for case statement.]"
						end
						
						options = template_params['options'].split(',').collect {|val| strip_quotes(val) }
						values = template_params['values'].split(',').collect {|val| strip_quotes(val) }

						if options.length != values.length
							"[There must be as many options as values, no more or less.]"
						else
							_case = template_params['case']
							index = options.index(stored_data[:user_variables][_case])

							if index
								value = values[index]
							elsif options.index(params["param_#{_case}"])
								value = params["param_#{_case}"]
							elsif template_params['default']
								value = template_params['default']
							else
								error = "[Value not found.]"
							end
						end
					else
						value = template_params['value']
					end

					if error
						error
					else
						stored_data[:user_variables][template_params['store']] = value
						""
					end
				elsif template_params.has_key?('datasource')
					conf = get_conf
					datasource_name = template_params['datasource']
					datasource = conf['datasources'][datasource_name]

					if !datasource
						"[Datasource not found]"
					else
						connection = connect(datasource, template_params['database'])
						query = get_query_from_template(connection, query, stored_data[:request_params])
						cols, resultset = [nil, nil]
						begin
							cols, resultset = connection.query_table(query)
						rescue Object => e
							puts "Error running query #{query}"
							puts "Exception: {e.message}"
							puts e.backtrace

							raise e
						end

						if template_params.has_key?('store')
							stored_data[:user_variables][template_params['store']] = resultset
						elsif template_params['format'] == 'table'
							render_table(cols, resultset)
						elsif template_params['format'] == 'scalar'
							resultset[0][0]
						elsif ['line_chart', 'bar_chart', 'pie_chart'].include?(template_params['format'])
							emit_chart(template_params['format'].to_sym, resultset, cols, template_params['name'], template_params['title'], template_params['xtitle'], template_params['ytitle'], template_params['height'].to_i, template_params['width'].to_i)
						end
					end
				elsif template_params.has_key?('fetch')
					value = stored_data[:user_variables][template_params['fetch']]

					if value == nil
						"[No value found for the key '#{template_params['fetch']}']"
					else
						if template_params.has_key?('format') && template_params['format'] == 'table'
							if (!template_params.has_key?('cols'))
								"[Tabular data cannot be specified without columns.]"
							else
								render_table(template_params['cols'].split(','), value)
							end
						else
							if value.is_a?(Array)
								value[0][0]
							else
								value
							end
						end
					end
				else
					"[No command was recognized.]"
				end
			}

			redcloth = RedCloth.new(@page['content'])
			redcloth.extend FormTag

			@page['content'] = redcloth.to_html

			if params['cache'] == 'true'
				write_cached_page(@page_id, query_params, @page['content'])
				return redirect to(remove_cache_request(request.url, true)) 
			end
		end

		haml :show_page
	else
		@page = {}
		haml :edit_page
	end
end

post '/page/:page_id' do
	if params['delete_page'] == 'true'
		delete_page(params[:page_id])
		return redirect to("/")
	end

	if params['destroy_cache'] == 'true'
		destroy_cache(params[:page_id])
		return redirect to(request.url)
	end

	content = {
		'title' => params[:title],
		'content' => params[:content]
	}

	page_id = params[:page_id]

	write_page(page_id, content)

	redirect to("/page/#{page_id}")
end
