ENV['RACK_ENV'] = 'test'

require '../index.rb'
require 'rspec'
require 'rack/test'

describe 'wiki page:' do
	include Rack::Test::Methods

	def app
		Sinatra::Application
	end

	testdb_filename = File.dirname(__FILE__) + '/testdb.sqlite'

	before do
		File.delete(testdb_filename) if File.exists?(testdb_filename)

		db = Sequel.sqlite(testdb_filename)
		db.create_table :people do
			primary_key :id
			String :firstname
			String :lastname
			String :city
			String :country
		end

		db[:people].insert(:firstname => 'Jeff', :lastname => 'Barman', :city => 'Oklahoma', :country => 'US')
		db[:people].insert(:firstname => 'Tim', :lastname => 'Falwell', :city => 'London', :country => 'UK')
		db[:people].insert(:firstname => 'June', :lastname => 'Tackwell', :city => 'Cambridge', :country => 'UK')
	end

	def query_ginger
		return if !block_given?

		gingerdb_filename = File.dirname(__FILE__) + '/data.sqlite'
		db = Sequel.sqlite(gingerdb_filename)
		yield(db)
	end

	def create_page(content, title='Test', page_path='test')
		post "/page/#{page_path}", :title => title, :content => content
		expect(last_response.redirect?).to be_true
	end

	def execute_page(content, title='Test', page_path='test')
		create_page(content, title, page_path)

		get "/page/#{page_path}"
		expect(last_response.ok?).to be_true
	end

	def page_should_contain(value)
		values = value.is_a?(Array) ? value : [value]

		values.each {|value|
			expect(last_response.body).to match(/#{value}/)
		}
	end

	def page_should_not_contain(value)
		expect(last_response.body).not_to match(/#{value}/)
	end

	def show_response
		puts last_response.body
	end

	context "simple page operations:" do
		it 'renders a page with no expressions' do
			execute_page 'World,' 'Hello', 'hello'

			expect(last_response.body).to match(/Hello/)
			expect(last_response.body).to match(/World/)
		end

		it 'can delete be deleted' do
			page_path = 'deletethis'

			execute_page 'hello', 'world', page_path

			deletethis_record = query_ginger {|db| db.fetch('select * from pages').all }.find {|record| record[:page_id] == page_path}
			expect(deletethis_record).not_to be_nil

			post("/page/#{page_path}", :delete_page => 'true', :submit => 'Delete')
			expect(last_response.redirect?).to be_true

			deletethis_record = query_ginger {|db| db.fetch('select * from pages').all }.find {|record| record[:page_id] == page_path}
			expect(deletethis_record).to be_nil
		end
	end

	context "Variables" do
		it 'can be set and retrieved' do
			execute_page '<: val="test value" :> <:val:> '
			page_should_contain 'test value'
		end

		it 'can be set conditionally based on another variable\'s value through the CASE statement' do
			execute_page '<: val1=a :><:case:val1:val2 (options=a,b,c values=one,two,three):><:val1=b:><:case:val1:val3 (options=a,b,c values=one,two,three):><:val2:><:val3:>'
			page_should_contain 'onetwo'
		end
	end

	context "Data" do
		it 'is displayed as a scalar value with only 1 column and row' do
			execute_page '[:localfile select \'random test\' :]'

			expect(last_response.body).to match(/random test/)
		end

		it 'is dispayed as a table when there are multiple rows and columns' do
			execute_page '[:localfile select * from people :]'

			page_should_contain %w(Jeff Tim June Barman Falwell Tackwell Oklahoma London Cambridge US UK)
		end

		it 'can forcibly be displayed in scalar format, even when there are multiple rows' do
			execute_page "start[:localfile:scalar select firstname from people where firstname='Jeff' :]end"
			page_should_contain 'startJeffend'
		end

		it 'can forcibly be displayed in tabular format, even when there is a single row and column' do
			execute_page "[:localfile:table select firstname from people where firstname='Jeff' :]"
			page_should_contain '<th>firstname</th>'
			page_should_contain '<td>Jeff</td>'
		end
	end

	context "Queries" do
		it 'can contain variables containing data declared without quotes' do
			execute_page "<:firstname=Jeff:>[:localfile select lastname from people where firstname='::firstname::' :]"
			page_should_contain 'Barman'
			page_should_not_contain 'Falwell'
			page_should_not_contain 'Tackwell'
		end

		it 'can contain variables containing data declared with quotes' do
			execute_page "<:clause=\"from people where firstname='Jeff'\":>[:localfile select lastname :clause: :]"
			page_should_contain 'Barman'
		end

		it 'run without the marked clause if the variable in the clause is not defined.' do
			execute_page "[:localfile select firstname from people {: where firstname='::firstname::' :} :]"
			page_should_contain 'Jeff'
			page_should_contain 'Tim'
			page_should_contain 'June'
		end

		it 'run with the marked clause if the variable in the clause is defined as a page variable.' do
			execute_page "<:firstname=Jeff:>[:localfile select lastname from people {: where firstname='::firstname::' :} :]"
			page_should_contain 'Barman'
			page_should_not_contain 'Falwell'
			page_should_not_contain 'Tackwell'
		end

		it 'run with the marked clause if the variable in the clause is defined as a form parameter.' do
			create_page "form. <:input:text (name=firstname title='First Name'):>\n\n[:localfile select lastname from people {: where firstname='::firstname::' :} :]"

			get '/page/test?p_firstname=Jeff'

			page_should_contain 'Barman'
			page_should_not_contain 'Falwell'
			page_should_not_contain 'Tackwell'
		end

		it 'run without the marked clause if the variable it checks does not exist' do
			execute_page "[:localfile select firstname from people {:firstname? where firstname='::firstname::' :} :]"
			page_should_contain 'Jeff'
			page_should_contain 'Tim'
			page_should_contain 'June'
		end

		it 'run with the marked clause if the variable it checks is defined as a page variable' do
			execute_page "<:testvalue=1:>[:localfile select lastname from people {:testvalue? where firstname='Jeff' :} :]"
			page_should_contain 'Barman'
			page_should_not_contain 'Falwell'
			page_should_not_contain 'Tackwell'
		end

		it 'uses a data sources specified in a variable' do
			execute_page "<:people=localfile:>[:{:people:} select firstname from people :]"

			page_should_contain 'Jeff'
			page_should_contain 'Tim'
			page_should_contain 'June'
		end
	end

	context "Display format" do
		it 'can be a pie chart' do
			execute_page "[:localfile:pie select firstname, 1 from people :]"
			page_should_contain('google.visualization.PieChart')
		end
		
		it 'can be a bar graph' do
			execute_page "[:localfile:bar select firstname, 1 from people :]"
			page_should_contain('google.visualization.BarChart')
		end

		it 'can be a line graph' do
			execute_page "[:localfile:line select firstname, 1 from people :]"
			page_should_contain('google.visualization.LineChart')
		end

		it 'can include a title for the x and/or y axes' do
			execute_page "[:localfile:line (xtitle='x test' ytitle='y test') select firstname, 1 from people :]"

			page_should_contain('google.visualization.LineChart')
			page_should_contain("vAxis: {title: 'y test'}")
			page_should_contain("hAxis: {title: 'x test'}")
		end
	end

	context "Forms" do
		it "can contain a dropdown with fixed values" do
			execute_page "form. <:input:dropdown (name=country options=US,India,China values=us,india,cn title=Country) :>"
			page_should_contain %w(p_country [Country] us US india India cn China option select submit Query)
		end

		it "can contain a dropdown with values queried from a database" do
			execute_page "form. [:localfile:dropdown (name=person title=Person option_column=firstname value_column=id) select id, firstname from people :]"
			page_should_contain %w(select p_person Jeff 1 Tim 2 June 3 submit Query)
		end

		it "can contain a textbox" do
			execute_page "form. <:input:text (name=city title=City) :>"
			page_should_contain %w(p_city City textbox submit Query)
		end
	end

	context "Text expressions" do
		it "will display replace the contained variable reference with the value of the variable" do
			execute_page "<: city=Mumbai :>{:My city is :city::}"
			page_should_contain "My city is Mumbai"
		end

		it "can hide themselves if the variable they contain is not defined." do
			execute_page "{:My city is :city::}"
			page_should_not_contain "My city is"
		end
	end

	context "Side by side formatting" do
		it "displays tables with the float:left style" do
			execute_page "<:sidebyside:>\n[:localfile select firstname from people :]\n\n<:sidebyside:>\n[:localfile select firstname from people :]\n<:sidebyside:end:>"
			page_should_contain %w(table style firstname Jeff Tim June)
			page_should_contain 'float:left'
			page_should_contain 'clear: both'
			page_should_not_contain '\|'
		end
	end

	context "Conditional formatting" do
		it "can change the color of a cell's text depending on it's value" do
			execute_page "[:localfile:table when val = 1 then text:green select 1 as val :]"
			page_should_contain '<td> <span style="color:green;">1</span></td>'

			execute_page "[:localfile:table when val = 'Jeff' then text:green select 'Jeff' as val :]"
			page_should_contain '<td> <span style="color:green;">Jeff</span></td>'
		end

		it "can change the background of a cell depending on it's value" do
			execute_page "[:localfile:table when val = 1 then background:green select 1 as val :]"
			page_should_contain '<td style="background-color: green;">1</td>'

			execute_page "[:localfile:table when val = 'Jeff' then background:green select 'Jeff' as val :]"
			page_should_contain '<td style="background-color: green;">Jeff</td>'
		end

		it "can change the weight of the text in a cell depending on it's value" do
			execute_page "[:localfile:table when val = 1 then bold, italics,underline select 1 as val :]"
			page_should_contain "<td> <ins><em><strong>1</strong></em></ins></td>"
		end

		it "can change the style of a cell if it has a value" do
			execute_page "[:localfile:table when val then bold, italics,underline select 1 as val :]"
			page_should_contain "<td> <ins><em><strong>1</strong></em></ins></td>"
		end

		it "can replace a value in a cell that matches a rule with another value based on a template" do
			execute_page "[:localfile:table when val then format:'val=%%' select 1 as val :]"
			page_should_contain "<th>val</th>"
			page_should_contain "<td> val=1</td>"
		end

		it "will not format cells if the values do not match" do
			execute_page "[:localfile:table when val=2 then bold, italics,underline select 1 as val :]"
			page_should_contain "<th>val</th>"
			page_should_contain "<td> 1</td>"

			execute_page "[:localfile:table when val>1 then bold, italics,underline select 1 as val :]"
			page_should_contain "<th>val</th>"
			page_should_contain "<td> 1</td>"

			execute_page "[:localfile:table when val<1 then bold, italics,underline select 1 as val :]"
			page_should_contain "<th>val</th>"
			page_should_contain "<td> 1</td>"
		end
	end

	context "CSV format" do
		it "renders queries in csv format" do
			create_page "[:localfile (id=testid) select * from people :]"

			get '/page/test?id=testid&format=csv'
			page_should_contain "'1','Jeff','Barman','Oklahoma','US'"
			page_should_contain "'2','Tim','Falwell','London','UK'"
			page_should_contain "'3','June','Tackwell','Cambridge','UK'"
		end
	end
end
