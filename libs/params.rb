def parse_params(params)
	matches = params.scan(/\w+=[\w,]+/)

	return [] if matches.length == 0

	Hash[*matches.collect {|v| v.split('=') }.flatten]
end

def execute_template(data, &procedure)
	matchable = data
	new_data = ''

	until (match = /<<=(.+)!!(.+)=>>/.match(matchable)) == nil
		params = match[1]
		query = match[2]

		if block_given?
			result = procedure.call(parse_params(params), query)
			new_data += match.pre_match + (result || '').to_s
		else
			new_data += match.pre_match + match[0]
		end

		matchable = match.post_match
	end

	new_data + matchable
end

#data = "abc def ghi <<= one=1 two=2 !! hello world blah =>> jkl mno"
#result = execute_template(data) {|params, query| "&&& #{params.inspect} || #{query} &&&&" }
#puts result

def param_to_sym(param)
	param.to_s.gsub(/\s+/, '_').gsub(/\.+/, '_').downcase.to_sym
end
