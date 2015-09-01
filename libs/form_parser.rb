require 'parslet'

class FormParser < Parslet::Parser
  rule(:whitespace) { match['\s'].repeat }

  rule(:string_without_single_quotes) { match["^'"].repeat(1) }
  rule(:single_quoted_string) { str('\'') >> (string_without_single_quotes >> str('\\\'')).repeat >> string_without_single_quotes >> str('\'') }

  rule(:string_without_double_quotes) { match['^"'].repeat }
  rule(:double_quoted_string) { str('"') >> (string_without_double_quotes >> str('\\"')).repeat >> string_without_double_quotes >> str('"') }

  rule(:quoted_string) { single_quoted_string | double_quoted_string }
  rule(:unquoted_word) { match['\w_'].repeat(1) }
  rule(:string) { quoted_string | unquoted_word }

  rule(:data_source_attribute) { whitespace >> str('data_source') >> whitespace >> str('=') >> whitespace >> string.as(:data_source_value) >> whitespace }
  rule(:table_name_attribute) { whitespace >> str('table') >> whitespace >> str('=') >> whitespace >> string.as(:table_name_value) >> whitespace }
  rule(:default_attribute) { whitespace >> str('default') >> whitespace >> str('=') >> whitespace >> string.as(:default_value) >> whitespace }
  rule(:column_attribute) { whitespace >> str('column') >> whitespace >> str('=') >> whitespace >> string.as(:column_value) >> whitespace }

  rule(:attributes) { whitespace >> (table_name_attribute | default_attribute | column_attribute).repeat >> whitespace }

  rule(:text_input) { whitespace >> str('[[text') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:textarea_input) { whitespace >> str('[[textarea') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:email_input) { whitespace >> str('[[email') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:password_input) { whitespace >> str('[[password') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:checkbox_input) { whitespace >> str('[[checkbox') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:radio_input) { whitespace >> str('[[radio') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:select_input) { whitespace >> str('[[select') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:multi_select_input) { whitespace >> str('[[multi_select') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:button_input) { whitespace >> str('[[button') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:date_input) { whitespace >> str('[[date') >> whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:time_input) { whitespace >> str('[[time') >>  whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }
  rule(:file_input) { whitespace >> str('[[file') >>  whitespace >> attributes >> whitespace >> str('/]]') >> whitespace }

  rule(:form_content) { (text_input.as(:text_input) | textarea_input.as(:textarea_input) | email_input.as(:email_input) | password_input.as(:password_input) | checkbox_input.as(:checkbox_input) | radio_input.as(:radio_input) | select_input.as(:select_input) | multi_select_input.as(:multi_select_input) | button_input.as(:button_input) | date_input.as(:date_input) | time_input.as(:time_input) | file_input.as(:file_input)).repeat }

  rule(:form) { str('[[form') >> whitespace >> data_source_attribute >> whitespace >> str(']]') >> whitespace >> form_content.as(:input_fields) >> whitespace >> str('[[/form]]') }

  rule(:document) { form.repeat.as(:form) }
  root(:document)
end