# frozen_string_literal: true

require "English"
require "net/http"

require_relative "zoho/version"
require_relative "zoho/metadata"
require_relative "zoho/cli"
require_relative "zoho/config"
require_relative "zoho/mail_api"
require_relative "zoho/handler"
require_relative "zoho/triage"

module Brainiac
  module Plugins
    module Zoho
      ZOHO_AUTH_SCOPES = "ZohoMail.messages.READ,ZohoMail.accounts.READ,ZohoMail.folders.READ"

      class << self
        # Called by Brainiac plugin system during server startup.
        #
        # @param app [Sinatra::Application] The running Brainiac server
        def register(app)
          Config.load!
          setup_routes(app)
          LOG.info "[Zoho] Plugin registered (webhook: /zoho)"
        end

        # Called after `brainiac install zoho` — creates config from template.
        def post_install(brainiac_dir)
          config_file = File.join(brainiac_dir, "zoho.json")
          return if File.exist?(config_file)

          template = File.expand_path("../../templates/zoho.json.example", __dir__)
          if File.exist?(template)
            FileUtils.cp(template, config_file)
          else
            default_config = {
              "hook_secret" => nil,
              "default_notify_target" => "",
              "notify_channel" => "discord",
              "notify_as" => "merlin",
              "rules" => [],
              "fallback" => { "enabled" => true, "label" => "Unmatched Email", "emoji" => "📬" }
            }
            File.write(config_file, JSON.pretty_generate(default_config))
          end
        end

        private

        def setup_routes(app)
          app.post "/zoho" do
            content_type :json
            request.body.rewind
            payload_body = request.body.read

            # Zoho sends X-Hook-Secret on the very first request — capture and store it
            hook_secret = request.env["HTTP_X_HOOK_SECRET"]
            if hook_secret
              Brainiac::Plugins::Zoho::Config.save_hook_secret(hook_secret)
              LOG.info "[Zoho] Received and stored hook_secret from initial handshake"
              halt 200, { status: "hook_secret_received" }.to_json
            end

            Brainiac::Plugins::Zoho.verify_signature!(request, payload_body)

            email = JSON.parse(payload_body)
            status_code, body = Brainiac::Plugins::Zoho::Handler.handle_webhook(email)
            halt status_code, body
          rescue JSON::ParserError => e
            LOG.error "[Zoho] Invalid JSON: #{e.message}"
            halt 400, { error: "Invalid JSON" }.to_json
          rescue StandardError => e
            LOG.error "[Zoho] Unhandled error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
            halt 500, { error: e.message }.to_json
          end

          app.get "/zoho/auth" do
            Brainiac::Plugins::Zoho::Config.reload!
            api = Brainiac::Plugins::Zoho::Config.api_section
            halt 500, "Missing client_id in zoho.json api section" unless api["client_id"]

            redirect_uri = "#{request.base_url}/zoho/callback"
            query_params = URI.encode_www_form(
              scope: ZOHO_AUTH_SCOPES,
              client_id: api["client_id"],
              response_type: "code",
              access_type: "offline",
              redirect_uri: redirect_uri,
              prompt: "consent"
            )
            redirect "https://accounts.zoho.com/oauth/v2/auth?#{query_params}"
          end

          app.get "/zoho/callback" do
            content_type :html
            code = params["code"]
            halt 400, "No authorization code received" unless code

            Brainiac::Plugins::Zoho::Config.reload!
            api = Brainiac::Plugins::Zoho::Config.api_section
            redirect_uri = "#{request.base_url}/zoho/callback"

            uri = URI(Brainiac::Plugins::Zoho::MailApi::ZOHO_TOKEN_URL)
            res = Net::HTTP.post_form(uri, {
                                        "grant_type" => "authorization_code",
                                        "client_id" => api["client_id"],
                                        "client_secret" => api["client_secret"],
                                        "code" => code,
                                        "redirect_uri" => redirect_uri
                                      })

            data = JSON.parse(res.body)
            if data["refresh_token"]
              Brainiac::Plugins::Zoho::Config.config["api"] ||= {}
              Brainiac::Plugins::Zoho::Config.config["api"]["refresh_token"] = data["refresh_token"]
              Brainiac::Plugins::Zoho::MailApi.store_token(data["access_token"])
              Brainiac::Plugins::Zoho::Config.save_config!
              LOG.info "[Zoho:OAuth] Stored refresh_token and access_token"

              unless Brainiac::Plugins::Zoho::Config.api_section["account_id"]
                acct_uri = URI(Brainiac::Plugins::Zoho::MailApi::ZOHO_MAIL_API_BASE.to_s)
                http = Net::HTTP.new(acct_uri.host, acct_uri.port)
                http.use_ssl = true
                req = Net::HTTP::Get.new(acct_uri)
                req["Authorization"] = "Zoho-oauthtoken #{data["access_token"]}"
                acct_res = http.request(req)
                acct_data = JSON.parse(acct_res.body)
                if (account_id = acct_data.dig("data", 0, "accountId"))
                  Brainiac::Plugins::Zoho::Config.config["api"]["account_id"] = account_id
                  Brainiac::Plugins::Zoho::Config.save_config!
                  LOG.info "[Zoho:OAuth] Auto-fetched account_id: #{account_id}"
                end
              end

              "<h1>✅ Zoho OAuth Complete</h1><p>Refresh token and account_id saved to zoho.json. You can close this tab.</p>"
            else
              LOG.error "[Zoho:OAuth] Token exchange failed: #{data}"
              "<h1>❌ OAuth Failed</h1><pre>#{data.to_json}</pre>"
            end
          rescue StandardError => e
            LOG.error "[Zoho:OAuth] Error: #{e.message}"
            "<h1>❌ Error</h1><pre>#{e.message}</pre>"
          end
        end
      end

      # Verify the X-Hook-Signature header (base64 HMAC-SHA256 of the raw body).
      def self.verify_signature!(request, payload_body)
        signature = request.env["HTTP_X_HOOK_SIGNATURE"]
        return unless signature

        secret = Config.hook_secret
        halt 500, { error: "No hook_secret configured — waiting for initial Zoho handshake" }.to_json unless secret

        computed = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, payload_body))
        halt 403, { error: "Invalid Zoho signature" }.to_json unless Rack::Utils.secure_compare(signature, computed)
      end
    end
  end
end
