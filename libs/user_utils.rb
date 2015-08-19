def user
  UserSQLiteStore.new
end

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
end