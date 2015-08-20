def data_source
  DataSourceSQLiteStore.new
end

class DataSourceSQLiteStore < SQLiteStore
  def load(data_source_name)
    data_source = db[:data_sources].where(data_source_name: data_source_name).first
    if data_source
    then
      # Load the attributes
      data_source_attributes = db[:data_source_attributes].where(data_source_name: data_source_name)
      to_hash(data_source_name, data_source_attributes)
    else
      nil
    end
  end

  def to_hash(data_source_name, attributes)
    attributes_hash = {}
    attributes.each{|attr| attributes_hash[param_to_sym(attr[:attribute_name])] = attr[:attribute_value] }
    {
      :name => data_source_name,
      :attributes => attributes_hash
    }
  end

  def save(data_source_name, attributes)
    existing_data_source = load(data_source_name)

    if existing_data_source != nil
    then
      db[:data_source_attributes].where(data_source_name: data_source_name).delete
    else
      db[:data_sources].insert(data_source_name: data_source_name)
    end

    attributes.each{|attr| db[:data_source_attributes].insert(data_source_name: data_source_name, attribute_name: attr[:name], attribute_value: attr[:value]) }
  end

  def list

  end

  def delete(data_source_name)
    db[:data_sources].where(data_source_name: data_source_name).delete
    db[:data_source_attributes].where(data_source_name: data_source_name).delete
  end
end