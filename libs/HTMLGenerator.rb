require './libs/ExecutionContext.rb'
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
		key = parameters[:text_expression][:variable].to_s
		value = nil

		if stored_data[:request_params][key]
			value = stored_data[:request_params][key][:value]
		else
			value = stored_data[:user_variables][key]
		end

		if value != nil
			return text(to_text(parse_redcloth(parameters[:text_expression][:pre_text].to_s) + value + to_text(parameters[:text_expression][:post_text].to_s)))
		else
			return empty_text
		end
	end

	def parse_redcloth(content)
		redcloth = RedCloth.new(content)
		redcloth.extend FormTag
		redcloth.to_html(content)
	end

	def process_erb(parameters)
		erb = ERB.new((parameters[:erb] || nil).to_s, nil, '%')
		text(erb.result(ExecutionContext.new(@stored_data)._binding))
	end

	def process_text(parameters)
		{text: parse_redcloth(parameters[:text])}
	end

	def process_sidebyside(parameters)
		if parameters[:sidebyside][:end]
			text("<div style='clear: both;'></div>")
		else
			text("table{float:left; margin-right:10px; margin-bottom: 10px}.")
		end
	end

	def process_assign(parameters)
		stored_data[:user_variables][parameters[:assign][:key].to_s] = parameters[:assign][:value].to_s
		empty_text
	end

	def process_reference(parameters)
		text((stored_data[:user_variables][parameters[:reference][:key].to_s] || '').to_s)
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

	def process_data(parameters)
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
							"#{to_text(item[:expression][:pre_text])}#{value}#{to_text(item[:expression][:post_text])}"
						elsif request_params.has_key?(variable_name)
							value = request_params[variable_name][:value] || ""
							type = request_params[variable_name][:type]

							value = format(connection, value, type)
							"#{to_text(item[:expression][:pre_text])}#{value}#{to_text(item[:expression][:post_text])}"
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
