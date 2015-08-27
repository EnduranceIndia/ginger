class UserSQLiteStore < SQLiteStore
  def exists(username)
    user = db[:users].where(username: username).first
    user != nil
  end

  def add_user(username)
    unless exists(username)
      db[:users].insert(username: username)
    end
  end

  def load(username)
    user = db[:users].where(username: username).first
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
    entry != nil
  end
end