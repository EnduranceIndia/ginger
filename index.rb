require 'json'
require 'uri'

require './libs/params'
require './config'

require './libs/page_utils'
require './libs/database'
require './libs/stop_evaluation'
require './libs/ginger_parser'

require 'rubygems'
require 'sinatra'
require 'redcloth'

base_files_directory = get_conf['base_files_directory']

def parse_param_data(template_params)
	name = strip_quotes(template_params['name'].to_s)
	title = strip_quotes(template_params['title'].to_s)
	type = strip_quotes(template_params['type'].to_s)

	return name, title, type
end

def store_param_data(stored_data, template_params, params, name, title, type)
	param_name = "p_#{name}"

	if params.has_key?(param_name) && params[param_name].length > 0
		stored_data[:request_params][name] = {:value => params[param_name], :type => type}
	else
		if (template_params['required'].to_s || "").downcase == 'true'
			raise StopEvaluation.new(title)
		end
	end
end

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

	options = "var options = {"
	options += " title: #{title}," if title
	options += " height: #{height}," if height
	options += " width: #{width}," if width

	options += "colors: ['#D3D3D3'], vAxis: {title: #{ytitle}}, hAxis: {title: #{xtitle}}" if [:bar_chart, :line_chart].include?(chart_type)

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

def format(connection, value, type)
	return "#{connection.escape(value)}" if type == 'string'
	return value
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
	stored_data = {
		:request_params => {
		},
		:user_variables => {
		}
	}


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
			begin
				pieces = parse_ginger_doc(@page['content'])
				puts pieces.inspect

				pass1 = []
				pass2 = []

				pieces.each_with_index {|*piece_with_index|
					piece, index = piece_with_index

					if piece[:data]
						pass2 << piece_with_index
					else
						pass1 << piece_with_index
					end
				}

				def empty_text
					return {:text => ''}
				end

				def text(val)
					return {:text => val}
				end

				processors = {}

				processors[:text] = proc {|parameters| parameters }

				processors[:sidebyside] = proc {|parameters|
					if parameters[:sidebyside][:end]
						text("<div style='clear: both;'></div>")
					else
						text("table{float:left; margin-right:10px; margin-bottom: 10px}.")
					end
				}

				processors[:assign] = proc {|parameters|
					stored_data[:user_variables][parameters[:assign][:key].to_s] = parameters[:assign][:value].to_s
					empty_text
				}

				processors[:reference] = proc {|parameters|
					text((stored_data[:user_variables][parameters[:reference][:key].to_s] || '').to_s)
				}

				processors[:input] = proc {|parameters|
					template_params = parameters[:input][:arguments]

					case parameters[:input][:type].to_s
					when 'submit'
						text("<input type=\"submit\" value=\"Query\"></input>")
					when 'text'
						if !template_params.has_key?('name')
							text("[No name specified for input field.]")
						elsif !template_params.has_key?('type')
							text("[No type specified for input field.]")
						elsif !template_params.has_key?('title')
							text("[No title specified for input field.]")
						else
							name, title, type = parse_param_data(template_params)
							store_param_data(stored_data, template_params, params, name, title, type)
							text("#{title} <input type='textbox' name='p_#{name}'></input>")
						end
					when 'dropdown'
						if !template_params.has_key?('name')
							text("[No name specified for input field.]")
						elsif !template_params.has_key?('type')
							text("[No type specified for input field.]")
						elsif !template_params.has_key?('title')
							text("[No title specified for input field.]")
						elsif !template_params.has_key?('options')
							text("[No options have been specified for input #{template_params['name']}.]")
						elsif !template_params.has_key?('values')
							text("[No values have been specified for input #{template_params['name']}.]")
						else
							options = template_params['options'].to_a.collect {|item| item.to_s }
							values = template_params['values'].to_a.collect {|item| item.to_s }

							if options.length != values.length
								text("[Options and values of input #{template_params['name']} are not of equal length.]")
							else
								name, title, type = parse_param_data(template_params)
								store_param_data(stored_data, template_params, params, name, title, type)

								html = "<span><select name=p_#{name}><option value=''>[#{title}]</option>"

								options.zip(values).each {|option, id|
									option = strip_quotes(option)
									selected_state = params["p_#{name}"] == id ? "selected=true" : ""
									html += "<option value='#{id}' #{selected_state}>#{option}</option>"
								}

								html += "</select></span>"

								text(html)
							end
						end
					end
				}

				processors[:case] = proc {|parameters|
					template_params = parameters[:case][:arguments]

					if !template_params.has_key?('options')
						text("[options have not been specified for case statement.]")
					elsif !template_params.has_key?('values')
						text("[values have not been specified for case statement.]")
					end
					
					options = template_params['options']
					values = template_params['values']

					if options.length != values.length
						text("[There must be as many options as values, no more or less.]")
					else
						source = parameters[:case][:source].to_s
						destination = parameters[:case][:destination].to_s

						error = nil

						index_of_value = options.index(stored_data[:user_variables][source])

						if index_of_value == nil
							index_of_value = options.index(stored_data[:request_params][source][:value])
						end

						if index_of_value != nil
							stored_data[:user_variables][destination] = strip_quotes(values[index_of_value])
						elsif template_params['default']
							stored_data[:user_variables][destination] = strip_quotes(template_params['default'])
						else
							error = text("[Value not found.]")
						end

						error || empty_text
					end
				}
				
				processors[:data] = proc {|parameters|
					template_params = parameters[:data][:arguments] || {}
					
					conf = get_conf

					datasource_name = nil

					if parameters[:data][:datasource_variable]
						datasource_name = stored_data[:user_variables][parameters[:data][:datasource_variable].to_s]
					else
						datasource_name = parameters[:data][:datasource].to_s
					end

					datasource = conf['datasources'][datasource_name]
					
					error = nil
					
					if !datasource
						text("[Datasource not found]")
					else
						connection = connect(datasource, template_params['database'])

						query = parameters[:data][:query]

						if !query.is_a?(Array)
							query = query.to_s
						else
							query = parameters[:data][:query].collect {|item|
								if item[:text]
									item[:text]
								elsif item[:variable]
									variable_name = item[:variable]	.to_s

									if stored_data[:user_variables].has_key?(variable_name)
										(stored_data[:user_variables][variable_name] || "")
									elsif request_params.has_key?(variable_name)
										value = request_params[variable_name][:value] || ""
										type = request_params[variable_name][:type]

										format(connection, value, type)
									end
								elsif item[:expression]
									variable_name = item[:expression][:variable].to_s

									if stored_data[:user_variables].has_key?(variable_name)
										value = (stored_data[:user_variables][variable_name] || "")
									elsif request_params.has_key?(variable_name)
										value = request_params[variable_name][:value] || ""
										type = request_params[variable_name][:type]

										value = format(connection, value, type)
									else
										item.inspect
									end

									to_text = proc {|val| val.is_a?(Array) ? "" : val.to_s }

									"#{to_text.call(item[:expression][:pre_text])}#{value}#{to_text.call(item[:expression][:post_text])}"
								end
							}.join
						end

						cols, resultset = [nil, nil]
						
						begin
							cols, resultset = connection.query_table(query)
						rescue Object => e
							puts "Error running query #{query}"
							puts "Exception message: #{e.message}"
							puts e.backtrace

							error = "[Error running query: #{query}]<br />"
							error += "[Exception message: #{e.message}]<br />"
							error += e.backtrace.join("<br />")
						end

						if error
							text(error)
						elsif template_params.has_key?('store')
							stored_data[:user_variables][template_params['store'].to_s] = resultset
							empty_text
						elsif parameters[:data][:format].to_s == 'table'
							text(render_table(cols, resultset))
						elsif parameters[:data][:format].to_s == 'scalar'
							text(resultset[0][0].to_s)
						elsif ['line', 'bar', 'pie'].include?(parameters[:data][:format].to_s)
							text(emit_chart(parameters[:data][:format].to_s.to_sym, resultset, cols, template_params['name'], template_params['title'], template_params['xtitle'], template_params['ytitle'], template_params['height'].to_i, template_params['width'].to_i))
						else
							if resultset.length == 1 && resultset[0].length == 1
								text((resultset[0][0] || "nil").to_s)
							else
								text(render_table(cols, resultset))
							end
						end
					end
				}

				pieces.each_with_index {|piece, index|
					result = processors[piece.keys[0]].call(piece)
					pieces[index] = result
				}

				@page['content'] = pieces.collect {|piece| piece[:text] ? piece[:text] : piece.inspect }.join

				redcloth = RedCloth.new(@page['content'])
				redcloth.extend FormTag

				@page['content'] = redcloth.to_html

				if params['cache'] == 'true'
					write_cached_page(@page_id, query_params, @page['content'])
					return redirect to(remove_cache_request(request.url, true)) 
				end
			rescue StopEvaluation => e
				@page['content'] = e.message
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
