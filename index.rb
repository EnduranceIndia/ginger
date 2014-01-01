require 'json'
require 'uri'

require './libs/params'
require './config'

require './libs/page_utils'
require './libs/database'
require './libs/stop_evaluation'
require './libs/ginger_parser'
require './libs/HTMLGenerator.rb'
require './libs/common_utils.rb'

require 'rubygems'
require 'sinatra'
require 'redcloth'

base_files_directory = get_conf['base_files_directory']

def template_to_html(content, params)
	convertors = []

	convertors = [
		proc {|content| r = parse_ginger_doc(content); puts r; r },
		proc {|content| HTMLGenerator.new(params).generate(content) },
		proc {|content|
			redcloth = RedCloth.new(content)
			redcloth.extend FormTag
			redcloth.to_html(content)
		}
	]

	new_content = content

	convertors.each {|convertor|
		new_content = convertor.call(new_content)
	}

	return new_content
end

def parse_param_data(template_params)
	name = strip_quotes(template_params['name'].to_s)
	title = strip_quotes(template_params['title'].to_s)
	type = strip_quotes(template_params['type'].to_s)

	return name, title, type
end

def store_param_data(stored_data, template_params, params, name, title, type)
	param_name = "p_#{name}"

	if params.has_key?(param_name) && params[param_name].length > 0
		stored_data[:request_params][name] = {:value => params[param_name], :type => type}
	else
		if (template_params['required'].to_s || "").downcase == 'true'
			raise StopEvaluation.new(title)
		end
	end
end

def add_cache_request(url)
	return if url.index('cache=true') != nil
	return url + '&cache=true' if url.index('?') != nil
	return url + '?cache=true'
end

def remove_cache_request(url, cache_switch)
	return "" if url == nil
	clean_url = url.gsub(/&cache=#{cache_switch}/, "")
	clean_url = clean_url.gsub(/\?cache=#{cache_switch}/, "")
	clean_url = clean_url.gsub(/cache=#{cache_switch}/, "") if clean_url.index("cache=#{cache_switch}") == 0
	clean_url = clean_url.gsub(/\?\s*$/, "")

	return clean_url
end

get '/' do
	@list_of_pages = list_of_pages
	haml :page_list
end

get '/explore/:datasource' do
	template = "[:#{params['datasource']} show tables; :]"

	@page = {}
	@page['content'] = template_to_html(template, params)

	haml :show_page
end

get '/explore/:datasource/:table' do
	template = "[:#{params['datasource']} desc #{params['table']}; :]"

	@page = {}
	@page['content'] = template_to_html(template, params)

	haml :show_page
end

get '/page/:page_id/edit' do
	@page_id = params[:page_id]
	@page = nil

	if page_exists(@page_id)
		@page = load_page(@page_id)
	end

	haml :edit_page
end

get '/page/:page_id' do
	stored_data = {
		:request_params => {
		},
		:user_variables => {
		}
	}


	@page_id = params[:page_id]

	if page_exists(@page_id)
		@page = load_page(@page_id)

		uri = URI.parse(request.url)

		query_params = remove_cache_request(uri.query, true) || ""
		last_modified_time, cached_page = get_cached_page(@page_id, query_params)

		if params['cache'] != 'true' && cached_page
			@page['content'] = cached_page
			cached_time = Time.now - last_modified_time

			minute = 60
			hour = 60 * minute
			day = 24 * hour

			if cached_time / minute < 2
				@cached_time = "#{cached_time.round} seconds"
			elsif cached_time / hour < 2
				@cached_time = "#{(cached_time / minute).round} minutes"
			elsif cached_time / day < 2
				@cached_timecached_time = "#{(cached_time / hour).round} hours"
			else
				@cached_timecached_time = "#{(cached_time / day).round} days"
			end

			@cached_time = "This page was cached #{@cached_time} ago."
		else
			begin
				@page['content'] = template_to_html(@page['content'], params)

				if params['cache'] == 'true'
					write_cached_page(@page_id, query_params, @page['content'])
					return redirect to(remove_cache_request(request.url, true)) 
				end
			rescue StopEvaluation => e
				@page['content'] = e.message
			end
		end

		haml :show_page
	else
		@page = {}
		haml :edit_page
	end
end

post '/page/:page_id' do
	if params['delete_page'] == 'true'
		delete_page(params[:page_id])
		return redirect to("/")
	end

	if params['destroy_cache'] == 'true'
		destroy_cache(params[:page_id])
		return redirect to(request.url)
	end

	content = {
		'title' => params[:title],
		'content' => params[:content]
	}

	page_id = params[:page_id]

	write_page(page_id, content)

	redirect to("/page/#{page_id}")
end
