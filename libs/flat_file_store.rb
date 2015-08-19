class FlatFileStore
  def exists?(page_id)
    File.exists?("#{get_conf[:base_files_directory]}/pages/#{page_id}")
  end

  def load(page_id)
    JSON.parse(File.read(get_page_file_path(page_id)))
  end

  def get_page_file_path(page_id)
    "#{get_conf[:base_files_directory]}/pages/#{page_id}"
  end

  def save(page_id, content)
    if page_id.include?('/') || page_id.include?('..')
      raise 'Cannot create a page containing either / or ..'
    end

    page_file_path = get_page_file_path(page_id)
    File.open(page_file_path, 'w+') { |f| f.write JSON.dump(content) }

    destroy_cache(page_id)
  end

  def list
    return [] unless File.exists?("#{get_conf[:base_files_directory]}/pages")
    Dir.entries("#{get_conf[:base_files_directory]}/pages").reject { |file| file.index('.') == 0 }
  end

  def delete(page_id)
    destroy_cache(page_id)
    page_file_path = get_page_file_path(page_id)
    File.delete(page_file_path) if File.exists?(page_file_path)
  end
end
