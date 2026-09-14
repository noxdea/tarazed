# frozen_string_literal: true

require_relative "tarazed/version"
require_relative "tarazed/cell"
require_relative "tarazed/scrollback"
require_relative "tarazed/grid"
require_relative "tarazed/vt"
require_relative "tarazed/pty"

module Tarazed
  class Error < StandardError; end
end
