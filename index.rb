require 'rubygems'
require 'sinatra'
require 'redcloth'
require 'erb'
require 'fileutils'
require 'sqlite3'
require 'pg'
require 'mysql'
require 'sequel'
require 'time'
require 'json'
require 'uri'
require 'parallel'
require 'net/ldap'
require 'parslet'

BASE = File.dirname(__FILE__)

require "#{BASE}/libs/params"
require "#{BASE}/config"

require "#{BASE}/libs/flat_file_store"
require "#{BASE}/libs/sqlite_store"
require "#{BASE}/libs/page_utils"
require "#{BASE}/libs/database"
require "#{BASE}/libs/stop_evaluation"
require "#{BASE}/libs/ginger_parser"
require "#{BASE}/libs/content_generator"
require "#{BASE}/libs/html_generator"
require "#{BASE}/libs/csv_generator"
require "#{BASE}/libs/common_utils"
require "#{BASE}/libs/execution_context"
require "#{BASE}/libs/ldap_auth"
require "#{BASE}/libs/user_utils"
require "#{BASE}/libs/data_source_utils"
require "#{BASE}/libs/group_utils"

class Ginger < Sinatra::Base

  enable :sessions

  set(:auth) do |*_|
    condition do
      unless session[:logged_in]
        redirect to('/login')
      end
    end
  end

  def template_to_html(content, params)
    converters = [
        proc { |content_value| parse_ginger_doc(content_value) },
        proc { |content_value| HTMLGenerator.new(params).generate(content_value) },
        proc { |content_value|
          redcloth = RedCloth.new(content_value)
          redcloth.extend FormTag
          redcloth.to_html(content_value)
        }
    ]

    new_content = content

    converters.each { |converter|
      new_content = converter.call(new_content)
    }

    new_content
  end

  def store_param_data(stored_data, template_params, params, name, title, type)
    param_name = "p_#{name}"

    if params.has_key?(param_name) && params[param_name].length > 0
      stored_data[:request_params][name] = {:value => params[param_name], :type => type}
    else
      if (template_params[:required].to_s || '').downcase == 'true'
        raise StopEvaluation.new(title)
      end
    end
  end

  def add_cache_request(url)
    return if url.index('cache=true') != nil
    return url + '&cache=true' if url.index('?') != nil
    url + '?cache=true'
  end

  def remove_cache_request(url, cache_switch)
    return '' if url == nil
    clean_url = url.gsub(/&cache=#{cache_switch}/, '')
    clean_url = clean_url.gsub(/\?cache=#{cache_switch}/, '')
    clean_url = clean_url.gsub(/cache=#{cache_switch}/, '') if clean_url.index("cache=#{cache_switch}") == 0
    clean_url.gsub(/\?\s*$/, '')
  end

  get '/', :auth => [:user] do
    redirect to('/my/pages')
  end

  get '/login' do
    if session[:logged_in]
      redirect to('/')
    end
    haml :login
  end

  post '/login' do
    username = params[:username]
    password = params[:password]

    ldap_auth_result = ldap_authenticate(username, password)

    if ldap_auth_result[:status] == 'authenticated'
      user.add_user(username)
      session[:logged_in] = true
      session[:username] = username
      redirect to('/')
    else
      session[:logged_in] = false
      session[:username] = ''
      redirect to('/login')
    end
  end

  get '/logout' do
    session[:logged_in] = false
    session[:username] = ''
    redirect to('/')
  end

  get '/explore', :auth => [:user] do
    @data_source_list = data_sources.list.keys
    haml :list_data_sources
  end

  get '/explore/:data_source', :auth => [:user] do

    data_source_name = params[:data_source]
    data_source = data_sources.list[param_to_sym(data_source_name)]

    db = connect(data_source)

    template = "h3. List of tables\n"

    template += db.query_tables.collect { |table|
      "* \"#{table.to_s}\":/explore/#{data_source_name}/#{table.to_s}"
    }.join("\n")

    @page = {
        :content => template_to_html(template, {})
    }

    haml :show_page
  end

  get '/explore/:data_source/:table', :auth => [:user] do
    data_source_name = params[:data_source]
    data_source = data_sources.list[param_to_sym(data_source_name)]

    db = connect(data_source)

    template = "h3. Schema of \"#{params[:table]}\"\n\ntable(table table-compact).\n|_. Name|_. Data Type |_. Primary Key |_. Allow null |\n"

    template += db.fields_for(params[:table]).collect { |field|
      "|#{field[:name]}|#{field[:db_type]}|#{field[:primary_key.to_s]}|#{field[:allow_null]}|"
    }.join("\n")

    @page = {
        :content => template_to_html(template, {})
    }

    haml :show_page
  end

  get '/data_source/:data_source_name/edit', :auth => [:user] do
    @data_source_name = params[:data_source_name]
    @data_source = nil

    @page_title = 'Edit Data Source'

    @data_source =
        data_source.load(@data_source_name)

    haml :edit_data_source
  end

  get '/data_source/:data_source_name/', :auth => [:user] do
    redirect to("/data_source/#{params[:data_source_name]}")
  end

  get '/data_source/:data_source_name', :auth => [:user] do
    @data_source_name = params[:data_source_name]

    @data_source = data_source.load(@data_source_name)

    if @data_source
      haml :show_data_source
    else
      @page_title = 'New Data Source'
      @data_source = {}
      @data_source[:name] = @data_source_name
      haml :edit_data_source
    end
  end

  post '/data_source/:data_source_name', :auth => [:user] do
    data_source_name = params[:name]
    attributes_string = params[:attributes]
    data_source.save(data_source_name, attr_string_to_hash(attributes_string), session[:username])
    redirect to("/data_source/#{params[:data_source_name]}")
  end

  get '/pages', :auth => [:user] do
    @list_of_pages = page.list
    haml :list_pages
  end

  get '/page/:page_id/edit', :auth => [:user] do
    @page_id = params[:page_id]
    @page = nil

    @page_title = 'Edit page'

    @page = page.load(@page_id)

    haml :edit_page
  end

  get '/page/:page_id/', :auth => [:user] do
    redirect to("/page/#{params[:page_id]}")
  end

  get '/page/:page_id', :auth => [:user] do
    @page_id = params[:page_id]

    @page = page.load(@page_id)

    if @page
      uri = URI.parse(request.url)

      query_params = remove_cache_request(uri.query, true) || ''
      last_modified_time, cached_page = get_cached_page(@page_id, query_params)

      if params[:id]
        parse_tree = parse_ginger_doc(@page[:content])
        content_type 'text/plain'

        CSVGenerator.new(params).generate(parse_tree)
      elsif params[:cache] != 'true' && cached_page
        @page[:content] = cached_page
        cached_time = Time.now - last_modified_time

        minute = 60
        hour = 60 * minute
        day = 24 * hour

        if cached_time / minute < 2
          cached_time = "#{cached_time.round} seconds"
        elsif cached_time / hour < 2
          cached_time = "#{(cached_time / minute).round} minutes"
        elsif cached_time / day < 2
          cached_time = "#{(cached_time / hour).round} hours"
        else
          cached_time = "#{(cached_time / day).round} days"
        end

        @cached_time = "This page was cached #{cached_time} ago."
      else
        begin
          @page[:content] = template_to_html(@page[:content], params)

          if params[:cache] == 'true'
            write_cached_page(@page_id, query_params, @page[:content])
            redirect to(remove_cache_request(request.url, true))
          end
        rescue StopEvaluation => e
          @page[:content] = e.message
        end
      end

      haml :show_page
    else
      @page_title = 'New page'
      @page = {}
      haml :edit_page
    end
  end

  post '/page/:page_id', :auth => [:user] do
    if params[:delete_page] == 'true'
      page.delete(params[:page_id])
      redirect to('/')
    end

    if params[:destroy_cache] == 'true'
      destroy_cache(params[:page_id])
      redirect to(request.url)
    end

    content = {
        :title => params[:title],
        :content => params[:content]
    }

    page_id = params[:page_id]

    page.save(page_id, content, session[:username])

    redirect to("/page/#{page_id}")
  end

  get '/groups', :auth => [:user] do
    @group_list = group.list
    haml :list_groups
  end

  get '/groups/:group_name/', :auth => [:user] do
    redirect to("/group/#{params[:group_name]}")
  end

  get '/groups/:group_name', :auth => [:user] do
    @group_name = params[:group_name]

    @group = group.load(@group_name)

    if @group
    then
      haml :show_group
    else
      @page_title = 'New Group'
      @group = {}
      @group[:group_name] = @group_name
      haml :edit_group
    end
  end

  get '/groups/:group_name/edit', :auth => [:user] do
    @group_name = params[:group_name]
    @group = nil

    @page_title = 'Edit Group'

    @group = group.load(@group_name)

    haml :edit_group
  end

  post '/groups/:group_name', :auth => [:user] do
    group_name = params[:group_name]
    members_string = params[:members]
    group.save(group_name, members_string_to_list(members_string), session[:username])
    redirect to("/groups/#{params[:group_name]}")
  end

  get '/my/groups', :auth => [:user] do
    haml :my_groups
  end

  get '/my/data_sources', :auth =>  [:user] do
    haml :my_data_sources
  end

  get '/my/pages', :auth => [:user] do
    haml :my_pages
  end

  get '/help', :auth => [:user] do
    help_text = <<-END
h2. Variables

Set the value of "var" to "b":

<pre>
<: var=b :></pre>

Display the value of "var":

<pre>
<:var:></pre>

h2. Case statement

|_. Value of test "var" |_. Corresponding value of "var2" |
| a | 1 |
| b | 2 |
| c | 3 |

<br>

<pre>
<: var=b :>
<:case:var:var2 (options=a,b,c values=1,2,3)</pre>

The test may refer to either a variable or a form parameter. If a variable and a form parameter exist by the same name, the variable is given preference. You can display the value of var2, which would be 2 in this case, using:

<pre>
<:var2:></pre>

h2. Tabular data

In the statement below, people_data is the data source being queried. The query "select * from people" is executed against this data source, and the result is displayed in tabular format. Tabular format is the default when the result is multiple rows or columns.

<pre>
[:people_data select * from people :]</pre>

In the statement below, the result has a single row and column, so the output will be rendered as plain text without any table markup.

<pre>
[:people_data select count(*) from people :]</pre>

To explicitly choose plain text:

<pre>
[:people_data:scalar select count(*) from people :]
</pre>

and for tabular output:

<pre>
[:people_data:table select count(*) from people :]
</pre>

h2. Query expressions

<pre>
[:people_data select * from people {: where city='::city::' :}]</pre>

The where clause will be added only if the city variable exists. The value of city will be escaped, because it is enclosed in double colons. Values are not escaped when enclosed in a single colons, like so:

<pre>
[:people_data select * from people {: where age > :age: :}]</pre>

In the statement below, the where clauses will be added if city has been specified as a form parameter or variable.

<pre>
[:people_data select * from people {:city? where 1=2 :}]</pre>

To specify a data_source that is contained in a variable:

<pre>
<:ds_name=employee_ds:>
[:{:ds_name:} select * from people :]</pre>

This is useful when the data source needs to be changed based on some user specified input.

A case statement may be used to set a variable based on the value of the input, and that variable may be used as a data source:

<pre>
<:case:input:ds_name (options=1,2,3 ds_name=a,b,c) :>
[:{:ds_name:} select * from people :]</pre>

h2. Graphs

<pre>
[:people_data:pie select city, count(*) from people group by city :]</pre>

The result set would look something like this:

|_. Title |_. Value |
| Mumbai |  10 |
| Delhi | 20 |
| Bangalore | 30 |

<br>

In each row, the first column contains the title, and the second column contains corresponding value.

<pre>
[:people_data:bar (x_title='Some title' y_title='Some other title') select city, count(*) from people group by city :]</pre>

Bar and line charts are similar. x_title and y_title refer to the captions on the x and y axis, but are not compulsory.

h2. Forms

Forms allow the viewer of the page to supply values with which queries on the page may be parameterized. They are ideally declared at the top of the page. They must be described using the following syntax:

<pre>
form. <:input:dropdown (name=country options=US,India,China values=us,india,cn title=Country) :></pre>

A form declaration must be on a single line. The submit button at the end of the form declaration is at this time essential.

Here are the currently supported form fields.

h4. Dropdown

<pre>
<:input:dropdown (name=country options=US,India,China values=us,india,cn title=Country) :></pre>

A dropdown will b displayed showing the options US, India, China, with corresponding values us, india and cn. When supplied by the user, they will be available in a variable named "country". The title of the dropdown will be displayed as "Country".

A dropdown can also be specified in terms of a database query, like so:

<pre>
[:people_data:dropdown (name=name title=Name option_column=name value_column=id) select * from people :]
</pre>

In this example, the name column of the result is what will be displayed in the dropdown box, and the corresponding id column is the value sent back for this field when the query button is pressed.

h4. Textbox

<pre>
<:input:text (name=city title=City) :></pre>

h2. Text expressions

<pre>
<: city=mumbai :>
{: display this if :city: is specified :}</pre>

This displays "display this if mumbai is specified" given that the value of "city" is "mumbai". But if no such variable exists, the entire expression is rendered as an empty string. "city" may also refer to a form parameter.

<pre>
{:city? display this if a city is specified :}</pre>

Displays "display this if a city is specified" if a form parameter or variable named city exists. If not, the entire expression is rendered as an empty string.

h2. Side-by-side panel formatting for tables

On the line before each table, put the following tag:

<pre>
<:side_by_side:></pre>

After all the side-by-side tables, put this tag:

<pre>
<:side_by_side:end></pre>

For example:

<pre>
<:side_by_side:>
[:people_data select * from people {: where city='::city::'' :} :]

<:side_by_side:>
[:people_data select * from people {:city? where age > 20 :} :]

<:side_by_side:>
[:people_data select * from people {:city? where state='::state::' :} :]

<:side_by_side:end:></pre>

h2. Conditional formatting

In the following table, any cell containing an age < 50 is highlighted with green, the rest with gray. The text is white.

The id column has been turned into a link using textile syntax, which is "Title" : http://url.com (without the spaces)

<pre>
[:people_data when id then format:'"id":http://go.to/%%' when age < 50 then background:green, text:white, bold when age >= 50 then background:gray, text:white select * from people :]</pre>

The syntax for specifying a condition and associated style looks like this: when column > value then style

These operators work on both numbers and words values: >, <, >=, <=, =, !=

Numbers are compare ordinally, and words are compared in alphabetical order.

Supported styles:
* bold, italics underline. Just use them like in the above example.
* Colors: may be specified as gray, green, etc. or in the #000, #000000 formats.
* Format: This is a primitive tool meant for replacing the value of a column with another value. The format must be specified in either single or double quotes. In the format template, %% is used to represent the column value.

h2. CSV format

To display a single query in csv format:

* give the query an id. e.g. [:people_data (id=test_id) select * from people :]
* formulate the url like this: http://hostname:port/page/pagename?id=test_id&format=csv

If you wish to change the quote, line separator or format separator, use the parameters in the url below:
http://hostname:port/page/pagename?id=test_id&format=csv&col_separator=%7C&quote="&line_separator=$

This url specifies The line separator as $, and the quote as ". The column separator is given as %7C, which is the url encoded value of the | character. Not all symbols need to be encoded like this. It is necessary only if the application displays an error.

    END

    @page = {
        :content => RedCloth.new(help_text).to_html
    }

    haml :show_page
  end
end