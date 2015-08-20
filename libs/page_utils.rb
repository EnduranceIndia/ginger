def page
  PageSQLiteStore.new
end

class PageSQLiteStore < SQLiteStore

  def load(page_id)
    page = db[:pages].where(page_id: page_id).first
    if page
    then
      to_hash(page)
    else
      nil
    end
  end

  def save(page_id, content)
    existing_page = load(page_id)

    if existing_page != nil
      db[:pages].where(page_id: page_id).update(title: content[:title], content: content[:content])
    else
      db[:pages].where(page_id: page_id).insert(page_id: page_id, title: content[:title], content: content[:content])
    end

    destroy_cache(page_id)
  end

  def to_hash(page)
    {
      :title => page[:title],
      :page_id => page[:page_id],
      :content => page[:content]
    }
  end

  def list
    db[:pages].collect { |page| {page_id: page[:page_id], title: page[:title]} }.sort { |page1, page2| page1[:title] <=> page2[:title] }
  end

  def delete(page_id)
    destroy_cache(page_id)
    db[:pages].where(page_id: page_id).delete
  end
end

def get_edit_link(url)
  uri = URI.parse(url)
  uri.path += '/edit'
  uri.to_s
end

def strip_quotes(val)
  val = (val || '').to_s.strip

  if (val[0] == '"' && val[val.length - 1] == '"') || (val[0] == '\'' && val[val.length - 1] == '\'')
    return val[1...val.length-1]
  end

  val
end

def destroy_cache(page_id)
  cache_file_path = "#{get_conf[:base_files_directory]}/cache/#{page_id}"
  FileUtils.rm_rf(cache_file_path) if Dir.exists?(cache_file_path)
end

def get_cache_file_name(page_id, params)
  base_path = "#{get_conf[:base_files_directory]}/cache/#{page_id}"

  return [base_path, params] if params && params.length > 0
  [base_path, page_id]
end

def get_cached_page(page_id, params)
  base_path, file_name = get_cache_file_name(page_id, params)

  path = base_path + '/' + file_name

  return [File.mtime(path), File.read(path)] if File.exists?(path)
  nil
end

def write_cached_page(page_id, params, content)
  base_path, file_name = get_cache_file_name(page_id, params)
  FileUtils.mkdir_p(base_path) unless Dir.exists?(base_path)
  path = base_path + '/' + file_name
  File.open(path, 'w+') { |f| f.write(content) }
end

def parse_params(params)
  matches = params.scan(/\w+=(?:\w+|::\w+::|"[\w ]+")(?:,(?:\w+|::\w+::|"[\w ]+"))*/)

  return {} if matches.length == 0

  Hash[*matches.collect { |v| v.split('=') }.flatten]
end

module FormTag
  def form(opts)
    "<form method=\"GET\" action=\"\">" + opts[:text] + " <input type='submit' value='Query'> </form>"
  end
end

def decimal_format(col)
  return ('%.2f' % col).to_s if col.is_a? BigDecimal
  col.to_s
end

def conditional_col_format(col_name, value, original_value, rules)
  return "|#{value.to_s}" if rules == nil || rules.length == 0

  column_start = '|'
  column_styles = []
  column_value = value.to_s

  rules.each { |rule|
    test_col_name = rule[:column].to_s
    next if test_col_name != col_name

    successes = 0
    successes += 1 if rule[:conditions].length == 0

    rule[:conditions].each { |condition|
      success = false
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
        return 'Conditional formatting does not recognize this value type.'
      end

      if condition[:operator] != nil
      then
        case condition[:operator].to_s
          when '>'
            success = (value.to_i > test_value.to_i)
          when '>='
            success = (value.to_i >= test_value.to_i)
          when '='
            success = (value.to_i == test_value.to_i)
          when '<'
            success = (value.to_i < test_value.to_i)
          when '<='
            success = (value.to_i <= test_value.to_i)
          when '!='
            success = (value.to_s != test_value.to_s)
          when 'gt'
            success = (value.to_s > test_value.to_s)
          when 'ge'
            success = (value.to_s >= test_value.to_s)
          when 'lt'
            success = (value.to_s < test_value.to_s)
          when 'le'
            success = (value.to_s <= test_value.to_s)
          when 'eq'
            success = (value.to_s == test_value.to_s)
          else
            success = false
        end
      end

      break unless success
      successes += 1
    }

    if successes >= rule[:conditions].length
      rule[:format].each { |style|
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
              else
            end
        end

      }
    end
  }

  column_style = column_styles.length > 0 ? "{#{column_styles.join(';')}}." : ''

  "#{column_start}#{column_style} #{column_value}"
end

def render_table(cols, result, markdown_table_class_added, conditional_formatting_rules)
  view = ''

  view += "table(table table-compact).\n" unless markdown_table_class_added

  view += '|_.' + cols.collect { |col| col.to_s }.join('|_.') + "|\n"

  conditional_formatting_rules = [conditional_formatting_rules] unless conditional_formatting_rules.is_a?(Array)

  view + result.collect { |row|
    cols.zip(row).collect { |col_name, value| conditional_col_format(col_name, decimal_format(value), value, conditional_formatting_rules) }.join + '|'
  }.join("\n")
end

def single_quoted(_)
  "'strip_quotes(val.to_s)'"
end

def double_quoted(_)
  "\"strip_quotes(val.to_s)\""
end

def emit_chart(chart_type, matrix, cols, _, title, x_title, y_title, height, width)
  matrix = matrix.clone
  matrix.unshift cols

  x_title = x_title || ''
  y_title = y_title || ''

  x_title = strip_quotes(x_title)
  y_title = strip_quotes(y_title)

  js_object_name = {:line => 'LineChart', :bar => 'ColumnChart', :pie => 'PieChart'}[chart_type]

  if js_object_name == nil
    return '[Chart type not recognized.]'
  end

  formatted_data = '[' + matrix.collect { |row|
    '[' + row.collect { |val|
      val.is_a?(String) ? "\"#{val}\"" : val.to_s
    }.join(',') + ']'
  }.join(',') + ']'

  width = strip_quotes(width) if width
  height = strip_quotes(height) if height

  options = 'var options = {'
  options += " title: '#{title}'," if title
  options += " height: '#{height}'," if height
  options += " width: '#{width}'," if width

  options += "colors: ['#D3D3D3'], vAxis: {title: '#{y_title}'}, hAxis: {title: '#{x_title}'}," if [:bar, :line].include?(chart_type)

  options += '};'

  width_clause = width != nil ? "width: #{width}; " : ''
  height_clause = height != nil ? "height: #{height}; " : ''

  name = (Random.new.rand * 100000).to_i.to_s

  "<script type=\"text/javascript\">
      google.load(\"visualization\", \"1\", {packages:[\"corechart\"]});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable(#{formatted_data});

        #{options}

        var chart = new google.visualization.#{js_object_name}(document.getElementById('#{name}'));
        chart.draw(data, options);
      } </script> <div id=\"#{name}\" style=\"#{width_clause} #{height_clause}\"></div>"
end

