ENV['RACK_ENV'] = 'development'

require '../index.rb'
require 'rspec'
require 'rack/test'

describe 'Ginger parser tests' do
	include Rack::Test::Methods

	def app
		Sinatra::Application
	end

	def parse(template)
		parse_ginger_doc(template)
	end

	it 'locates the data source in a data expression' do
		result = parse("[:peopledata select 1; :]")
		result[0][:data][:datasource].to_s.should eq('peopledata')
	end

	it 'locates the query in a data expression' do
		result = parse("[:peopledata select 1; :]")
		result[0][:data][:query][0][:text].to_s.strip.should eq('select 1;')
	end

	it 'correctly parses arguments with a single value' do
		result = parse("[:peopledata (arg1=1 arg2=2) select 1; :]")

		arguments = result[0][:data][:arguments]

		arguments.keys.length.should eq(2)
		arguments['arg1'].to_s.should eq('1')
		arguments['arg2'].to_s.should eq('2')
	end

	it 'correctly parses arguments with multiple values' do
		result = parse("[:peopledata (arg1=1 arg2=2,3) select 1; :]")

		arguments = result[0][:data][:arguments]

		arguments.keys.length.should eq(2)
		arguments['arg1'].to_s.should eq('1')
		arguments['arg2'].should eq(['2', '3'])
	end

	it 'shows arguments as nil if there are none' do
		result = parse("[:peopledata select 1; :]")

		result[0][:data][:arguments].should be(nil)
	end

	def validate_condition(condition, operation, value)
		condition[:operator].to_s.should eq(operation)
		condition[:value].to_s.should eq(value)
	end

	it 'parses conditional expressions with a single condition' do
		result = parse("[:testdb when b > 10 then bold select * from helloworld :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(1)

		rules[0][:conditions].length.should be(1)
		rules[0][:column].to_s.should eq('b')
		validate_condition(rules[0][:conditions][0], '>', '10')
	end

	it 'parses conditional expressions with multiple conditions' do
		result = parse("[:testdb when b > 10 and < 20 then bold select * from helloworld :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(1)

		rules[0][:conditions].length.should be(2)
		rules[0][:column].to_s.should eq('b')
		validate_condition(rules[0][:conditions][0], '>', '10')
		validate_condition(rules[0][:conditions][1], '<', '20')
	end

	it 'parses the existence condition' do
		result = parse("[:testdb when b then bold select * from helloworld :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(1)

		rules[0][:conditions].length.should be(0)
		rules[0][:column].to_s.should eq('b')
	end

	it 'parses a conditional expression with a single format' do
		result = parse("[:testdb when b > 10 then bold select * from helloworld :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(1)

		rules[0][:format].length.should be(1)
		rules[0][:format][0].to_s.should eq('bold')
	end

	it 'parses a conditional expression with multiple formats' do
		result = parse("[:testdb when b > 10 then bold,italics select * from helloworld :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(1)

		rules[0][:format].length.should be(2)
		rules[0][:format][0].to_s.should eq('bold')
		rules[0][:format][1].to_s.should eq('italics')
	end

	it 'parses a conditional expression with multiple formats' do
		result = parse("[:testdb when b > 10 then bold,italics select * from helloworld :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(1)

		rules[0][:format].length.should be(2)
		rules[0][:format][0].to_s.should eq('bold')
		rules[0][:format][1].to_s.should eq('italics')
	end

	def validate_conditions(rule, column, expected_conditions, expected_formats)
		rule[:column].to_s.should eq(column)

		expected_conditions = expected_conditions.each_slice(2).to_a

		(rule[:conditions] || []).length.should be(0) if (expected_conditions || []).length == 0

		rule[:conditions].zip(expected_conditions) {|actual, expected|
			actual[:operator].to_s.should eq(expected[0])
			actual[:value].to_s.should eq(expected[1])
		}

		(rule[:format] || []).length.should be(0) if (expected_formats || []).length == 0

		rule[:format].zip(expected_formats) {|actual, expected|
			actual.to_s.should eq(expected)
		}
	end

	it 'parses multiple conditional expressions with multiple formats' do
		result = parse("[:testdb when b > 10 and < 20 then bold,underline when a then green select 1; :]")
		rules = result[0][:data][:conditional_formatting]
		rules.length.should be(2)

		validate_conditions(rules[0], 'b', %w(> 10 < 20), %w(bold underline))
	end

	it 'identifies a variable name specified as a data source' do
		result = parse("[:$addresses (id=addreses) :]")
		result[0][:data][:data_variable].should eq('addresses')
	end

	it 'identifies a variable name that contains the name of a data source' do
		result = parse("[:{:ds:} (id=addreses) select * from people :]")
		result[0][:data][:datasource_variable].should eq('ds')
	end
end
