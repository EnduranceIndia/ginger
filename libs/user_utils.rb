def user
  UserSQLiteStore.new
end

class UserSQLiteStore < SQLiteStore
  def exists(username)
    user = db[:users].where(username: username).first
    self.close
    user != nil
  end

  def add_user(username)
    unless exists(username)
      db[:users].insert(username: username)
      self.close
    end
  end

  def load(username)
    user = db[:users].where(username: username).first
    self.close
    if user
    then
      to_hash(user)
    else
      nil
    end
  end

  def to_hash(user)
    {
      :username => user[:username]
    }
  end

  def is_admin(username)
    entry = db[:group_users].where(username: username, group_name: 'admin').first
    self.close
    entry != nil
  end
end