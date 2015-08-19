class StopEvaluation < Exception
  def initialize(title)
    @title = title
  end

  def message
    "[The parameter \"#{@title}\" was not specified, so this page cannot load beyond this point.]"
  end
end
