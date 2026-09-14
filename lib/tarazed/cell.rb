# frozen_string_literal: true

module Tarazed
  Cell = Struct.new(:text, :width, :foreground, :background, :attributes, :hyperlink, keyword_init: true)
end
