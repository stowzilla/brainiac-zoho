# frozen_string_literal: true

module Brainiac
  module Plugins
    module Zoho
      module Config
        CONFIG_FILE = File.join(ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac")), "zoho.json")

        @config = {}
        @last_mtime = nil

        class << self
          attr_reader :config

          def load!
            @config = load_config
            @last_mtime = File.exist?(CONFIG_FILE) ? File.mtime(CONFIG_FILE) : nil
          end

          def reload!
            return unless file_changed?

            @config = load_config
            @last_mtime = File.exist?(CONFIG_FILE) ? File.mtime(CONFIG_FILE) : nil
            LOG.info "[Zoho] Reloaded configuration"
          end

          def hook_secret
            @config["hook_secret"]
          end

          def save_hook_secret(secret)
            @config["hook_secret"] = secret
            File.write(CONFIG_FILE, JSON.pretty_generate(@config))
            LOG.info "[Zoho] Saved hook_secret to #{CONFIG_FILE}"
          end

          def default_notify_target
            @config["default_notify_target"]
          end

          def notify_channel
            @config["notify_channel"] || "discord"
          end

          def notify_as
            @config["notify_as"]
          end

          def rules
            @config["rules"] || []
          end

          def fallback
            @config["fallback"]
          end

          def triage_board_id
            @config["triage_board_id"]
          end

          def triage_project_tags
            tags = @config["triage_project_tags"]
            return "Use your best judgement to identify the relevant project." unless tags&.any?

            tags.map { |t| "  - `#{t["tag"]}` — #{t["description"]}" }.join("\n")
          end

          def triage_agent_assignment
            rules = @config["triage_agent_assignment"]
            return "Assign to the default agent." unless rules&.any?

            rules.map { |r| "  - #{r}" }.join("\n")
          end

          def api_section
            @config["api"] || {}
          end

          def api_configured?
            api = api_section
            api["client_id"] && api["client_secret"] && api["refresh_token"] && api["account_id"]
          end

          def save_config!
            File.write(CONFIG_FILE, JSON.pretty_generate(@config))
          end

          private

          def load_config
            return {} unless File.exist?(CONFIG_FILE)

            JSON.parse(File.read(CONFIG_FILE))
          rescue JSON::ParserError => e
            LOG.error "[Zoho] Failed to parse config: #{e.message}"
            {}
          end

          def file_changed?
            return false unless File.exist?(CONFIG_FILE)

            current_mtime = File.mtime(CONFIG_FILE)
            return false if @last_mtime && current_mtime == @last_mtime

            @last_mtime = current_mtime
            true
          end
        end
      end
    end
  end
end
