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

	rule(:query_variable) { str('::') >> unquoted_word.as(:variable) >> str('::') }
	rule(:query_expression) { str('<') >> (query_variable.absent? >> any).repeat.as(:pre_text) >> query_variable >> match['^>'].repeat.as(:post_text) >> str('>') }
	rule(:query_text_fragment) { (query_expression.absent? >> query_variable.absent? >> str(':]').absent? >> any).repeat(1) }
	rule(:query) { (query_text_fragment.as(:text) | query_expression.as(:expression) | query_variable).repeat }
	rule(:datasource_variable) { str('::') >> unquoted_word.as(:datasource_variable) >> str('::') }
	rule(:data) { str('[:') >> (unquoted_word.as(:datasource) | datasource_variable) >> (str(':') >> unquoted_word.as(:format)).maybe >> whitespace >> arguments.maybe.as(:arguments) >> whitespace >> query.as(:query) >> whitespace >> str(':]') }

	rule(:input) { open_bracket >> str('input:') >> unquoted_word.as(:type) >> whitespace >> arguments.maybe.as(:arguments) >> whitespace >> close_bracket }

	rule(:switch_case) { open_bracket >> str('case:') >> unquoted_word.as(:source) >> str(':') >> unquoted_word.as(:destination) >> whitespace >> arguments.as(:arguments) >> whitespace >> close_bracket }

	rule(:sidebyside) { open_bracket >> str('sidebyside') >> str(':end').maybe.as(:end) >> whitespace >> close_bracket }

	rule(:text_expression) { str('<:').absent? >> str('<') >> match['^:<\['].repeat.as(:pre_text) >> str('::') >> unquoted_word.as(:variable) >> str('::') >> match['^:>\]'].repeat.as(:post_text) >> str('>') }
	rule(:erb) { str('<%') >> str('=').maybe >> (str('%>').absent? >> any).repeat >> str('%>') }

	rule(:expression) { erb.as(:erb) | text_expression.as(:text_expression) | sidebyside.as(:sidebyside) | assign.as(:assign) | reference.as(:reference) | switch_case.as(:case) | input.as(:input) | data.as(:data) }

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
	end

	transform.apply(result)
end
