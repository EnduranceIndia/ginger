require 'rubygems'
require 'parslet'

class GingerParser < Parslet::Parser
	rule(:string_without_single_quotes) { match["^'"].repeat(1) }
	rule(:single_quoted_string) { str('\'') >> (string_without_single_quotes >> str('\\\'')).repeat >> string_without_single_quotes >> str('\'') }

	rule(:string_without_double_quotes) { match['^"'].repeat }
	rule(:double_quoted_string) { str('"') >> (string_without_double_quotes >> str('\\"')).repeat >> string_without_double_quotes >> str('"') }

	rule(:quoted_string) { single_quoted_string | double_quoted_string }
	rule(:unquoted_word) { match['\w_'].repeat(1) }
	rule(:string) { quoted_string | unquoted_word }
	rule(:whitespace) { match['\s'].repeat }

	rule(:sequence) { ((quoted_string | unquoted_word).as(:value) >> str(',')).repeat >> string.as(:value) }

	rule(:open_bracket) { str('<:') }
	rule(:close_bracket) { str(':>') }

	rule(:assign) { open_bracket >> whitespace >> unquoted_word.as(:key) >> whitespace >> str('=') >> whitespace >> string.as(:value) >> whitespace >> close_bracket }

	rule(:reference) { open_bracket >> whitespace >> unquoted_word.as(:key) >> whitespace >> close_bracket }

	rule(:arguments) { str('(') >> (whitespace >> unquoted_word.as(:key) >> whitespace >> str('=') >> whitespace >> (sequence | string).as(:value)).repeat >> str(')') }

	rule(:unescaped_query_variable) { str(':') >> unquoted_word.as(:variable) >> str(':') }
	rule(:escaped_query_variable) { str('::') >> unquoted_word.as(:escaped_variable) >> str('::') }
	rule(:query_variable) { unescaped_query_variable | escaped_query_variable }
	rule(:check_query_variable_exists) { unquoted_word.as(:check_query_variable_exists) >> str('?') }
	rule(:check_variable_value) { unquoted_word.as(:check_variable_key) >> str('=') >> string.as(:check_variable_value) >> str('?') }
	rule(:variable_check) { (check_query_variable_exists | check_variable_value).repeat(1).as(:variable_checks) }
	rule(:query_expression) { str('{:') >> variable_check.maybe >> (query_variable.absent? >> str(':}').absent? >> any).repeat.as(:pre_text) >> query_variable.maybe >> (str(':}').absent? >> any).repeat.as(:post_text) >> str(':}') }
	rule(:query_text_fragment) { (query_expression.absent? >> query_variable.absent? >> str(':]').absent? >> any).repeat(1) }
	rule(:query) { (query_text_fragment.as(:text) | query_expression.as(:expression) | query_variable).repeat }
	rule(:data_source_variable) { str('{:') >> unquoted_word.as(:data_source_variable) >> str(':}') }
	
	rule(:style_token) { unquoted_word >> (str(':') >> string).maybe }
	rule(:styles) { (style_token.as(:value) >> whitespace >> str(',') >> whitespace).repeat >> style_token.as(:value) }
	rule(:condition) { (str('=') | str('>=') | str('>') | str('<=') | str('<') | str('!=')).as(:operator) >> whitespace >> (match['\w_.'].repeat(1) | quoted_string).as(:value) }
	rule(:conditional_formatting) {((str('when') >> whitespace >> ((unquoted_word.as(:column) >> whitespace >> str('then') >> whitespace >> styles.as(:format)) | (unquoted_word.as(:column) >> whitespace >> ((condition >> whitespace >> str('and') >> whitespace).repeat >> condition).as(:conditions) >> whitespace >> str('then') >> whitespace >> styles.as(:format)))) >> whitespace).as(:rule).repeat }
	rule(:data_variable) { str('$') >> unquoted_word.as(:data_variable) }

	rule(:data) { str('[:') >> variable_check.maybe >> (unquoted_word.as(:data_source) | data_source_variable | data_variable) >> (str(':') >> unquoted_word.as(:format)).maybe >> whitespace >> arguments.maybe.as(:arguments) >> whitespace >> (conditional_formatting.as(:conditional_formatting) >> whitespace).maybe >> query.as(:query) >> whitespace >> str(':]') }

	rule(:input) { open_bracket >> str('input:') >> unquoted_word.as(:type) >> whitespace >> arguments.maybe.as(:arguments) >> whitespace >> close_bracket }

	rule(:switch_case) { open_bracket >> str('case:') >> unquoted_word.as(:source) >> str(':') >> unquoted_word.as(:destination) >> whitespace >> arguments.as(:arguments) >> whitespace >> close_bracket }

	rule(:side_by_side) { open_bracket >> str('side_by_side') >> str(':end').maybe.as(:end) >> whitespace >> close_bracket }

	rule(:text_variable) { str(':') >> unquoted_word.as(:variable) >> str(':') }
	rule(:check_text_variable_exists) { check_query_variable_exists }
	rule(:text_expression) { str('{:') >> variable_check.maybe >> (text_variable.absent? >> str(':}').absent? >> any).repeat.as(:pre_text) >> text_variable.maybe >> (str(':}').absent? >> any).repeat.as(:post_text) >> str(':}') }

	rule(:ruby_code) { str('[%') >> ((str('%]').absent? >> str('"').absent? >> str("'").absent? >> any) | quoted_string).repeat.as(:code) >> str('%]') }

	rule(:expression) { text_expression.as(:text_expression) | side_by_side.as(:side_by_side) | assign.as(:assign) | reference.as(:reference) | switch_case.as(:case) | input.as(:input) | data.as(:data) | ruby_code }

	rule(:text) { (expression.absent? >> any).repeat(1) }

	rule(:document) { ( text.as(:text) | expression).repeat }

	root(:document)
end

def parse_ginger_doc(doc)
	parser = GingerParser.new
	result = parser.parse(doc)

	args_transformer = proc {|tree_type, d|
		arguments = d[:tree][:arguments]

		if arguments and arguments.is_a? Array
			values = []
			arguments.each {|arg| values << arg[:key].to_s << (arg[:value].is_a?(Array) ? arg[:value].collect {|val| val.to_s } : arg[:value].to_s) }
			d[:tree][:arguments] = Hash[*values]
		end

		{tree_type => d[:tree]}
	}

	transform = Parslet::Transform.new do
		rule({:value => simple(:value)}) {|d| d[:value] }

		[:data, :input, :case].each {|tree_type|
			rule({tree_type => subtree(:tree)}) {|d| args_transformer.call(tree_type, d) }
		}

		rule({rule: {column: simple(:column), conditions: subtree(:conditions), format: subtree(:format)}}) {|d|
			conditions = d[:conditions].is_a?(Array) ? d[:conditions] : [d[:conditions]]
			format = d[:format].is_a?(Array) ? d[:format] : [d[:format]]

			{column: d[:column], conditions: conditions, format: format}
		}

		rule(rule: {column: simple(:column), format: subtree(:format)}) {|d|
			format = d[:format].is_a?(Array) ? d[:format] : [d[:format]]

			{column: d[:column], conditions: [], format: format}
		}
	end

	transform.apply(result)
end
