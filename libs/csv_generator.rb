class CSVGenerator < ContentGenerator
  def initialize(params)
    super(params)
  end

  def csv_col_formatter(val, quote)
    "#{quote}#{val}#{quote}"
  end

  def render_csv(cols, result)
    quote = params[:quote] || "'"
    col_separator = params[:col_separator] || ','
    line_separator = params[:line_separator] || "\n"

    header = cols.collect { |col| csv_col_formatter(col, quote) }.join(col_separator)

    rows = result.collect { |row| row.collect { |col| csv_col_formatter(col, quote) }.join(col_separator) }.join(line_separator)

    header + line_separator + rows
  end

  def process_data(parameters)
    return text('') unless variable_checks_passed(parameters[:data])

    @markdown_table_class_added = nil

    request_params = stored_data[:request_params]
    template_params = parameters[:data][:arguments] || {}

    conf = get_conf

    if parameters[:data][:data_source_variable]
      data_source_name = stored_data[:user_variables][parameters[:data][:data_source_variable].to_s]
    else
      data_source_name = parameters[:data][:data_source].to_s
    end

    data_source = data_sources.list[param_to_sym(data_source_name)]

    error = nil

    if !data_source
      text('[Data source not found]')
    else
      connection = connect(data_source, template_params[:database])

      query = parameters[:data][:query]

      if !query.is_a?(Array)
        query = query.to_s
      else
        query = parameters[:data][:query].collect { |item|
          if item[:text]
            item[:text]
          elsif item[:variable]
            variable_name = item[:variable].to_s

            if stored_data[:user_variables].has_key?(variable_name)
              strip_quotes(stored_data[:user_variables][variable_name] || '')
            elsif request_params.has_key?(variable_name)
              strip_quotes(request_params[variable_name][:value] || '')
            end
          elsif item[:escaped_variable]
            variable_name = item[:escaped_variable].to_s
            value = nil

            if stored_data[:user_variables].has_key?(variable_name)
              value = (stored_data[:user_variables][variable_name] || '')
            elsif request_params.has_key?(variable_name)
              value = request_params[variable_name][:value] || ''
            end

            strip_quotes(escape(connection, strip_quotes(value)))
          elsif item[:expression]
            if variable_checks_passed(item[:expression])
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
                  ''
                end
              else
                "#{to_text(item[:expression][:pre_text])}"
              end
            else
              ''
            end
          end
        }.join
      end

      cols, result_set = [nil, nil]

      begin
        cols, result_set = connection.query_table(query)
      rescue Object => e
        puts "Error running query #{query}"
        puts "Exception message: #{e.message}"
        puts e.backtrace

        error = "[Error running query: #{query}]<br />"
        error += "[Exception message: #{e.message}]<br />"
        error += e.backtrace.join('<br />')
      end

      if error
        text(error)
      else
        render_csv(cols, result_set)
      end
    end
  end

  def generate(parse_tree)
    parse_tree.each { |piece|
      if piece[:data] == nil
        processor = 'process_' + piece.keys[0].to_s
        self.send(processor, piece)
      end
    }

    id = @params[:id].to_s

    piece = parse_tree.find { |piece|
      piece[:data] != nil && piece[:data][:arguments] != nil && piece[:data][:arguments][:id].to_s == id
    }

    process_data(piece)
  end
end
