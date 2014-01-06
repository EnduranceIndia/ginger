require './libs/ExecutionContext.rb'
require './libs/page_utils.rb'
require 'erb'

class HTMLGenerator
	attr_accessor :stored_data, :params

	def initialize(params)
		@stored_data = {:user_variables => {}, :request_params => {}}
		@params = params
	end

	def empty_text
		return {:text => ''}
	end

	def text(val)
		return {:text => val}
	end

	def process_text_expression(parameters)
		if parameters[:text_expression][:check_query_variable_exists] != nil
			key = parameters[:text_expression][:check_query_variable_exists].to_s

			if stored_data[:request_params][key] == nil
				return text("")
			end
		end

		key = parameters[:text_expression][:variable]

		if key == nil
			returnable_data = to_text(parameters[:text_expression][:pre_text]) + to_text(parameters[:text_expression][:post_text])
			return text(returnable_data)
		end

		key = key.to_s
		value = nil

		if stored_data[:request_params][key]
			value = stored_data[:request_params][key][:value]
		else
			value = stored_data[:user_variables][key]
		end

		if value != nil
			value = (value || "").to_s

			return text(to_text(parameters[:text_expression][:pre_text]) + value + to_text(parameters[:text_expression][:post_text]))
		else
			return empty_text
		end
	end

	def process_erb(parameters)
		erb = ERB.new((parameters[:erb] || nil).to_s, nil, '%')
		text(erb.result(ExecutionContext.new(@stored_data)._binding))
	end

	def process_text(parameters)
		parameters
	end

	def process_sidebyside(parameters)
		if parameters[:sidebyside][:end]
			text("<div style='clear: both;'></div>")
		else
			@markdown_table_class_added = true
			text("table{float:left; margin-right:10px; margin-bottom: 10px}.")
		end
	end

	def process_assign(parameters)
		stored_data[:user_variables][parameters[:assign][:key].to_s] = parameters[:assign][:value].to_s
		empty_text
	end

	def process_reference(parameters)
		text(strip_quotes(stored_data[:user_variables][parameters[:reference][:key].to_s] || '').to_s)
	end

	def process_input(parameters)
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
	end

	def process_case(parameters)
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
	end

	def to_text(val)
		val.is_a?(Array) ? "" : val.to_s
	end

	def variable_check_passed(parameters)
		variable_existence_check = parameters[:check_query_variable_exists] != nil
		variable_value_check = parameters[:check_variable_key] != nil
		check_passed = true

		if variable_existence_check
			query_variable_to_check = parameters[:check_query_variable_exists]
			query_variable_to_check = query_variable_to_check.to_s if query_variable_to_check != nil

			check_passed = false if stored_data[:request_params][query_variable_to_check] == nil
		elsif variable_value_check
			checked_variable_key = parameters[:check_variable_key].to_s
			checked_variable_value = parameters[:check_variable_value]
			checked_variable_value = strip_quotes(checked_variable_value.to_s) if checked_variable_value != nil

			if stored_data[:request_params][checked_variable_key] != nil
				check_passed = false if stored_data[:request_params][checked_variable_key][:value] != checked_variable_value
			elsif stored_data[:user_variables][checked_variable_key] != nil
				check_passed = false if stored_data[:user_variables][checked_variable_key] != checked_variable_value
			else
				check_passed = false
			end
		end

		return check_passed
	end

	def process_data(parameters)
		if !variable_check_passed(parameters[:data])
			return text("")
		end

		markdown_table_class_added = @markdown_table_class_added
		@markdown_table_class_added = nil

		request_params = stored_data[:request_params]
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
							strip_quotes(stored_data[:user_variables][variable_name] || "")
						elsif request_params.has_key?(variable_name)
							strip_quotes(request_params[variable_name][:value] || "")
						end
					elsif item[:escaped_variable]
						variable_name = item[:escaped_variable].to_s

						if stored_data[:user_variables].has_key?(variable_name)
							value = (stored_data[:user_variables][variable_name] || "")
						elsif request_params.has_key?(variable_name)
							value = request_params[variable_name][:value] || ""
						end

						strip_quotes(escape(connection, strip_quotes(value)))
					elsif item[:expression]
						if variable_check_passed(item[:expression])
							variable_name = nil
							escaped = false

							variable_name = item[:expression][:variable].to_s if item[:expression][:variable]

							if item[:expression][:escaped_variable]
								variable_name = item[:expression][:escaped_variable].to_s
								escaped = true
							end
							
							if variable_name
								value = stored_data[:user_variables][variable_name]

								if value == nil && request_params[variable_name] != nil
									value = request_params[variable_name][:value]
								end

								if value != nil
									value = strip_quotes(escape(connection, strip_quotes(value))) if escaped
									"#{to_text(item[:expression][:pre_text])}#{value}#{to_text(item[:expression][:post_text])}"
								else
									""
								end
							else
								"#{to_text(item[:expression][:pre_text])}"
							end
						else
							""
						end
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
				text(render_table(cols, resultset, markdown_table_class_added))
			elsif parameters[:data][:format].to_s == 'scalar'
				text(resultset[0][0].to_s)
			elsif ['line', 'bar', 'pie'].include?(parameters[:data][:format].to_s)
				text(emit_chart(parameters[:data][:format].to_s.to_sym, resultset, cols, template_params['name'], template_params['title'], template_params['xtitle'], template_params['ytitle'], template_params['height'].to_i, template_params['width'].to_i))
			else
				if resultset.length == 1 && resultset[0].length == 1
					text((resultset[0][0] || "nil").to_s)
				else
					text(render_table(cols, resultset, markdown_table_class_added))
				end
			end
		end
	end

	def generate(parse_tree)
		pass1 = []
		pass2 = []

		parse_tree.each_with_index {|*piece_with_index|
			piece, index = piece_with_index

			if piece[:data]
				pass2 << piece_with_index
			else
				pass1 << piece_with_index
			end
		}

		pass1.each {|piece, index|
			processor = 'process_' + piece.keys[0].to_s
			result = self.send(processor, piece)
			parse_tree[index] = result
		}

		Parallel.map(pass2, :in_processes => 10) {|piece, index|
			processor = 'process_' + piece.keys[0].to_s
			[self.send(processor, piece), index]
		}.each {|result, index|
			parse_tree[index] = result
		}

		result = parse_tree.collect {|piece| piece[:text] ? piece[:text] : piece.inspect }.join
		return result
	end
end
