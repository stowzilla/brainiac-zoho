# frozen_string_literal: true

# Lightweight metadata for brainiac-zoho.
# Loaded by `brainiac help` without pulling in the full plugin runtime.

require_relative "version"

module Brainiac
  module Plugins
    module Zoho
      # Returns true if Zoho config file exists.
      def self.configured?
        config_file = File.join(ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac")), "zoho.json")
        File.exist?(config_file)
      rescue StandardError
        false
      end

      # Help text shown in `brainiac help` when the plugin is installed.
      def self.help_text
        "    brainiac zoho <command>       Manage Zoho Mail webhooks (setup, config, auth)"
      end
    end
  end
end
