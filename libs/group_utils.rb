def group
  GroupSQLiteStore.new
end

class GroupSQLiteStore < SQLiteStore
  def load(group_name)
    group = db[:groups].where(group_name: group_name).first
    self.close

    if group
    then
      to_hash(group)
    else
      nil
    end
  end

  def to_hash(group)
    {
      :group_name => group[:group_name]
    }
  end

  def save(group_name)
    existing_group = load(group_name)

    if existing_group == nil
    then
      db[:groups].insert(group_name: group_name)
    end

    self.close
  end

  def list
    groups = []
    db[:groups].collect do |group|
      groups.push(group[:group_name])
    end

    self.close
    groups
  end
end