# frozen_string_literal: true

module Brainiac
  module Plugins
    module Zoho
      module Cli
        class << self
          def run(args)
            command = args.shift
            case command
            when "setup" then cmd_setup
            when "config" then cmd_config
            when "auth" then cmd_auth
            else print_help
            end
          end

          private

          def cmd_setup
            brainiac_dir = ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac"))
            config_file = File.join(brainiac_dir, "zoho.json")

            if File.exist?(config_file)
              puts "Zoho config already exists at #{config_file}"
              return
            end

            template = File.expand_path("../../../../templates/zoho.json.example", __dir__)
            if File.exist?(template)
              FileUtils.cp(template, config_file)
              puts "Created #{config_file} from template"
            else
              puts "Template not found — creating minimal config"
              default_config = { "hook_secret" => nil, "default_notify_target" => "", "notify_channel" => "discord", "rules" => [],
                                 "fallback" => { "enabled" => true } }
              File.write(config_file, JSON.pretty_generate(default_config))
              puts "Created #{config_file}"
            end

            puts "Edit the file to configure notification rules."
          end

          def cmd_config
            brainiac_dir = ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac"))
            config_file = File.join(brainiac_dir, "zoho.json")

            unless File.exist?(config_file)
              puts "No Zoho config found. Run: brainiac zoho setup"
              return
            end

            config = JSON.parse(File.read(config_file))
            rules = config["rules"] || []
            puts "Zoho Configuration:"
            puts "  Config file: #{config_file}"
            puts "  Hook secret: #{config["hook_secret"] ? "captured" : "(pending — waiting for first webhook)"}"
            puts "  Default channel: #{config["default_notify_target"] || "(not set)"}"
            puts "  Notify channel: #{config["notify_channel"] || "discord"}"
            puts "  Notify as: #{config["notify_as"] || "(default)"}"
            puts "  Rules: #{rules.size} configured"
            rules.each { |r| puts "    - #{r["label"]} (#{r["enabled"] == false ? "disabled" : "enabled"})" }
            puts "  API configured: #{config.dig("api", "refresh_token") ? "yes" : "no"}"
          end

          def cmd_auth
            puts "Visit http://localhost:4567/zoho/auth in your browser to start OAuth flow."
            puts "Make sure brainiac server is running and zoho.json has api.client_id + api.client_secret."
          end

          def print_help
            puts "Usage: brainiac zoho <command>"
            puts ""
            puts "Commands:"
            puts "  setup     Create Zoho config file (~/.brainiac/zoho.json)"
            puts "  config    Show current Zoho configuration"
            puts "  auth      Instructions for OAuth setup"
          end
        end
      end

      # Plugin CLI entry points
      def self.cli(args)
        Cli.run(args)
      end

      def self.completions
        %w[setup config auth]
      end
    end
  end
end
