class FormSQLiteStore < SQLiteStore

  def load(form_id)

  end

  def get_permissions_hash(form_id)

  end

  def get_highest_permission(permissions_list)

  end

  def save(form_id, content, permissions, creator)

  end

  def to_hash(form, permissions_hash)

  end

  def to_displayable_hash(form, permissions_hash)

  end

  def list

  end

  def list_public

  end

  def list_created_by(username)

  end

  def list_shared_with(username)

  end

  def list_shared_with_user_groups(username)

  end

  def to_list(forms)

  end

  def delete(form_id)

  end

  def get_user_permissions(form_id, username)

  end

  def is_creator(form_id, username)

  end
end

def get_edit_link(url)

end