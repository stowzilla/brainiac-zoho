# frozen_string_literal: true

require "net/http"

module Brainiac
  module Plugins
    module Zoho
      module MailApi
        ZOHO_TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
        ZOHO_MAIL_API_BASE = "https://mail.zoho.com/api/accounts"

        @access_token = nil
        @token_expires_at = Time.at(0)

        class << self
          def configured?
            Config.api_configured?
          end

          def refresh_access_token!
            api = Config.api_section
            uri = URI(ZOHO_TOKEN_URL)
            res = Net::HTTP.post_form(uri, {
                                        "grant_type" => "refresh_token",
                                        "client_id" => api["client_id"],
                                        "client_secret" => api["client_secret"],
                                        "refresh_token" => api["refresh_token"]
                                      })

            data = JSON.parse(res.body)
            if data["access_token"]
              @access_token = data["access_token"]
              @token_expires_at = Time.now + 3300
              LOG.info "[Zoho:API] Refreshed access token"
              @access_token
            else
              LOG.error "[Zoho:API] Token refresh failed: #{data["error"]}"
              nil
            end
          rescue StandardError => e
            LOG.error "[Zoho:API] Token refresh error: #{e.message}"
            nil
          end

          def access_token
            return @access_token if @access_token && Time.now < @token_expires_at

            refresh_access_token!
          end

          # Store token obtained during OAuth callback
          def store_token(token)
            @access_token = token
            @token_expires_at = Time.now + 3300
          end

          def fetch_email_content(message_id)
            return nil unless configured?

            token = access_token
            return nil unless token

            account_id = Config.api_section["account_id"]
            uri = URI("#{ZOHO_MAIL_API_BASE}/#{account_id}/messages/#{message_id}/originalmessage")

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            req = Net::HTTP::Get.new(uri)
            req["Authorization"] = "Zoho-oauthtoken #{token}"
            req["Accept"] = "application/json"

            res = http.request(req)
            data = JSON.parse(res.body)

            if data.dig("status", "code") == 200
              raw_mime = data.dig("data", "content").to_s
              text = extract_text_from_mime(raw_mime)
              LOG.info "[Zoho:API] Fetched content for message #{message_id} (#{text.length} chars)"
              text
            else
              LOG.warn "[Zoho:API] Failed to fetch content: #{data.dig("status", "description")}"
              nil
            end
          rescue StandardError => e
            LOG.error "[Zoho:API] Error fetching content: #{e.message}"
            nil
          end

          private

          def extract_text_from_mime(mime)
            if mime =~ %r{Content-Type: text/plain[^\r\n]*\r?\n(?:Content-Transfer-Encoding:[^\r\n]*\r?\n)?(?:\r?\n)(.*?)(?:\r?\n------=_Part|\z)}mi
              return Regexp.last_match(1).gsub("\r\n", "\n").strip
            end

            if mime =~ %r{Content-Type: text/html[^\r\n]*\r?\n(?:Content-Transfer-Encoding:[^\r\n]*\r?\n)?(?:\r?\n)(.*?)(?:\r?\n------=_Part|\z)}mi
              html = Regexp.last_match(1).gsub("\r\n", "\n")
              return html.gsub(/<[^>]+>/, " ").gsub(/&nbsp;/i, " ").gsub(/&amp;/i, "&")
                         .gsub(/&lt;/i, "<").gsub(/&gt;/i, ">").gsub(/\s+/, " ").strip
            end

            mime.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
          end
        end
      end
    end
  end
end
