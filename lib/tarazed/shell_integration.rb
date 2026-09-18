# frozen_string_literal: true

module Tarazed
  module ShellIntegration
    NAMES = {bash: "tarazed.bash", zsh: "tarazed.zsh", fish: "tarazed.fish"}.freeze
    private_constant :NAMES

    module_function

    def path(shell)
      name = File.basename(shell.to_s).downcase.delete_suffix(".exe").to_sym
      file = NAMES.fetch(name) { raise ArgumentError, "unsupported shell: #{shell}" }
      File.expand_path("../../assets/shell-integration/#{file}", __dir__)
    end

    def read(shell) = File.binread(path(shell))
  end
end
