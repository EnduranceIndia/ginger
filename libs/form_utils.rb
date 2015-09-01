class FormSQLiteStore < SQLiteStore

  def load(form_id)
    form = db[:forms].where(form_id: form_id).first

    if form
    then
      to_displayable_hash(form, get_permissions_hash(form_id))
    else
      nil
    end
  end

  def get_permissions_hash(form_id)
    form_permissions = db[:form_permissions].where(form_id: form_id)

    permissions_hash = {}
    permissions_hash[:user] = {}
    permissions_hash[:group] = {}
    permissions_hash[:all] = {}

    form_permissions.each do |permission|
      permissions_hash[param_to_sym(permission[:entity])][param_to_sym(permission[:entity_name])] = permission[:permission]
    end

    permissions_hash
  end

  def get_highest_permission(permissions_list)
    permissions_priority = {
        :forbidden => 0,
        :write => 1,
        :edit => 2
    }

    current_permission = 'forbidden'

    permissions_list.each do |perm|
      permission = perm[:permission]
      if permissions_priority[param_to_sym(permission)] > permissions_priority[param_to_sym(current_permission)]
        current_permission = permission
      end
    end

    current_permission
  end

  def save(form_id, content, permissions, creator)
    existing_form = load(form_id)

    if existing_form != nil
      db[:forms].where(form_id: form_id).update(title: content[:title], content: content[:content])
      db[:form_permissions].where(form_id: form_id).delete
    else
      db[:forms].where(form_id: form_id).insert(form_id: form_id,
                                                title: content[:title],
                                                content: content[:content],
                                                creator: creator)
    end

    permissions.each do |entity, table|
      table.each do |entity_name, permission|
        db[:form_permissions].insert(form_id: form_id,
                                     entity: entity.to_s,
                                     entity_name: entity_name.to_s,
                                     permission: permission.to_s)
      end
    end
  end

  def to_hash(form, permissions_hash)
    {
        :title => form[:title],
        :form_id => form[:form_id],
        :content => form[:content],
        :user_permissions => permissions_hash_to_string(permissions_hash[:user]),
        :group_permissions => permissions_hash_to_string(permissions_hash[:group]),
        :all_permissions => permissions_hash_to_string(permissions_hash[:all])
    }
  end

  def to_displayable_hash(form, permissions_hash)
    {
        :title => form[:title],
        :form_id => form[:form_id],
        :content => form[:content],
        :user_permissions => permissions_hash_to_string(permissions_hash[:user]),
        :group_permissions => permissions_hash_to_string(permissions_hash[:group]),
        :all_permissions => permissions_hash_to_string(permissions_hash[:all])
    }
  end

  def list
    forms = db[:forms].collect
    to_list(forms)
  end

  def list_public
    forms = db[:forms].where(:form_id => db[:form_permissions].where(entity: 'all').where(entity_name: 'all').select(:form_id))
    to_list(forms)
  end

  def list_created_by(username)
    forms = db[:forms].where(creator: username)
    to_list(forms)
  end

  def list_shared_with(username)
    username = param_to_sym(username).to_s
    forms = db[:forms].where(:form_id => db[:form_permissions].where(entity_name: username).select(:form_id))
    to_list(forms)
  end

  def list_shared_with_user_groups(username)
    forms = db[:forms].where(:form_id => db[:form_permissions].where(entity: 'group').where(:entity_name => db[:group_users].where(username: username).select(:group_name)).select(:form_id))
    to_list(forms)
  end

  def to_list(forms)
    forms.each { |form| {form_id: form[:form_id], title: form[:title]} }.sort { |form1, form2| form1[:title] <=> form2[:title] }
  end

  def delete(form_id)
    db[:forms].where(form_id: form_id).delete
    db[:form_permissions].where(form_id: form_id).delete
  end

  def get_user_permissions(form_id, username)

    if is_creator(form_id, username)
      return 'edit'
    end

    username_str = username
    username = param_to_sym(username).to_s

    user_groups = db[:group_users].where(username: username_str).select(:group_name)
    permissions_list = db[:form_permissions].where(form_id: form_id).where{Sequel.|(Sequel.&({:entity => 'user'}, {:entity_name => username}), Sequel.&({:entity => 'group'}, {:entity_name => user_groups}), Sequel.&({:entity => 'all'}, {:entity_name => 'all'}))}.select(:permission).all

    self.get_highest_permission(permissions_list)
  end

  def is_creator(form_id, username)
    res = db[:forms].where(form_id: form_id, creator:  username).first
    res !=  nil
  end
end

def get_edit_link(url)
  uri = URI.parse(url)
  uri.path += '/edit'
  uri.to_s
end
