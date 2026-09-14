# frozen_string_literal: true

ENV["MT_NO_PLUGINS"] = "1"
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "rbconfig"
require "tmpdir"
require "tarazed"
