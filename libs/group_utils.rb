def group
  GroupSQLiteStore.new
end

class GroupSQLiteStore < SQLiteStore
  def load(group_name)
    group = db[:groups].where(group_name: group_name).first
    self.close

    if group
    then
      to_displayable_hash(group, get_members_list(group_name))
    else
      nil
    end
  end

  def get_members_list(group_name)
    group_members = db[:group_users].where(group_name: group_name)
    members_list = []
    group_members.each { |mapping| members_list.push(mapping[:username]) }
    self.close
    members_list
  end

  def to_hash(group, members_list)
    {
      :group_name => group[:group_name],
      :members_list => members_list
    }
  end

  def to_displayable_hash(group, members_list)
    {
        :group_name => group[:group_name],
        :members_list => members_list_to_string(members_list)
    }
  end

  def save(group_name, members, creator)
    existing_group = load(group_name)

    if existing_group == nil
    then
      db[:groups].insert(group_name: group_name, creator: creator)
    else
      db[:group_users].where(group_name: group_name).delete
    end

    members.push(creator)
    members = members.uniq

    members.each do |member_name|
      unless member_name.nil?
        db[:group_users].insert(group_name: group_name, username: member_name.to_s)
      end
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

  def list_created_by(username)
    groups_list = []

    groups = db[:groups].where(creator: username)

    groups.each do |group|
      groups_list.push(group[:group_name])
    end

    self.close
    groups_list
  end

  def list_user_groups(username)
    groups_list = []

    groups = db[:group_users].where(username: username)

    groups.each do |group|
      groups_list.push(group[:group_name])
    end

    self.close
    groups_list
  end

  def delete(group_name)
    db[:groups].where(group_name: group_name).delete
    db[:group_users].where(group_name: group_name).delete
    self.close
  end
end

def members_string_to_list(members_string)
  members_list = []

  members_string.split(';').each do |member_name|
    members_list.push(member_name)
  end

  members_list
end

def members_list_to_string(members_list)
  members_string = ''

  members_list.each do |member_name|
    members_string += "#{member_name};"
  end

  members_string
end

def get_group_edit_link(url)
  uri = URI.parse(url)
  uri.path += '/edit'
  uri.to_s
end
