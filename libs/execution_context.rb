class ExecutionContext
  def initialize(stored_data)
    @queries = []

    @default_allowed = ['[]']
    @allowed = @default_allowed

    @stored_data = stored_data

    @connections = {}
  end

  def ds
    self
  end

  def verify_validity(call)
    raise NotAllowedError.new("#{call} not allowed.") unless @allowed.include?(call)
  end

  def store(name)
    verify_validity('store')

    execute

    @stored_data[:user_variables][name] = @last_result
    nil
  end

  def [](data_source_name)
    verify_validity('[]')

    @data_source_name = data_source_name
    @allowed = ['query']

    self
  end

  def query(query, *params)
    verify_validity('query')

    @queries << {datasource_name: @data_source_name, query: query, params: params}
    @allowed = %w([] query store)

    self
  end

  def user_variables(key)
    @stored_data[:user_variables][key]
  end

  def get_data_source_connection(data_source_name=nil)
    data_source_name = data_source_name || @data_source_name

    if @connections[data_source_name] == nil
      data_source_info = get_conf[:data_sources][param_to_sym(data_source_name)]
      raise DataSourceNotFoundError.new(data_source_name) if data_source_info == nil

      @connections[data_source_name] = connect(data_source_info, nil)
    end

    @connections[data_source_name]
  end

  def request_param(key)
    return @stored_data[:request_params][key][:value] if @stored_data[:request_params].has_key?(key)
    raise RequestParamNotFound.new(key)
  end

  def request_param?(key)
    @stored_data[:request_params].has_key?(key)
  end

  def execute
    results = Parallel.map(@queries, :in_processes => 10) { |query_info|
      connection = get_data_source_connection(query_info[:@data_source_name])
      connection.query_table(query_info[:query], *query_info[:params])
    }

    @last_result = []

    if results.length > 0
      @last_result << results[0][0]
      @last_result << results.collect { |result| result[1].inject(:+) }
    end
  end

  def _binding
    binding
  end
end

class NotAllowedError < Exception
  attr_reader :message

  def initialize(message)
    @message = message
  end
end

class UntypedRequestParamError < Exception
  attr_reader :message

  def initialize(_)
    @message = 'Cannot return the value of an untyped form parameter.'
  end
end

class DataSourceNotFoundError < Exception
  attr_reader :message

  def initialize(data_source_name)
    @message = "Data source #{data_source_name} configuration not found."
  end
end

class RequestParamNotFound < Exception
  attr_reader :message

  def initialize(param_name)
    @message = "Request parameter #{param_name} not found."
  end
end
