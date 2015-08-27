module GingerResourceType
  PAGE = 1
  DATA_SOURCE = 2
  USER = 3
  GROUP = 4
end

class GingerResource
  def GingerResource.access(type)
    case type
      when GingerResourceType::PAGE
        resource = PageSQLiteStore.new
      when GingerResourceType::DATA_SOURCE
        resource = DataSourceSQLiteStore.new
      when GingerResourceType::USER
        resource = UserSQLiteStore.new
      when GingerResourceType::GROUP
        resource = GroupSQLiteStore.new
      else
        resource = nil
    end
    yield resource
  ensure
    resource.close
  end
end