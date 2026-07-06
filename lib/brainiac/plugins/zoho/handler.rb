# frozen_string_literal: true

module Brainiac
  module Plugins
    module Zoho
      module Handler
        class << self
          def handle_webhook(email)
            LOG.info "[Zoho] Received email: subject=#{email["subject"]}, from=#{email["fromAddress"]}, to=#{email["toAddress"]}"

            dump_payload(email)
            Config.reload!

            rule = match_rule(email)
            if rule
              LOG.info "[Zoho] Matched rule: #{rule["label"]}"
              if rule["dispatch_agent"]
                Triage.dispatch(email, rule)
                [200, { status: "triage_dispatched", rule: rule["label"], agent: rule["dispatch_agent"] }.to_json]
              else
                notify_match(email, rule)
                [200, { status: "matched", rule: rule["label"] }.to_json]
              end
            else
              LOG.info "[Zoho] No rules matched"
              [200, { status: "no_match" }.to_json]
            end
          end

          def match_rule(email)
            rules = Config.rules
            matched = rules.find { |rule| rule_matches?(rule, email) }
            return matched if matched

            fallback = fallback_rule
            return nil if fallback && email_excluded?(email, Config.fallback&.dig("exclude_words"))

            fallback
          end

          def rule_matches?(rule, email)
            return false if rule["enabled"] == false

            %w[from_contains to_contains subject_contains].each do |field|
              pattern = rule[field]
              next if pattern.nil? || pattern.empty?

              email_field = case field
                            when "from_contains" then email["fromAddress"]
                            when "to_contains" then email["toAddress"]
                            when "subject_contains" then email["subject"]
                            end
              return false unless email_field.to_s.downcase.include?(pattern.downcase)
            end

            if rule["body_contains"] && !rule["body_contains"].empty?
              body = "#{email["summary"]}#{email["html"]}"
              return false unless body.downcase.include?(rule["body_contains"].downcase)
            end

            !email_excluded?(email, rule["exclude_words"])
          end

          def email_excluded?(email, exclude_words)
            return false if exclude_words.nil? || exclude_words.empty?

            searchable = [email["subject"], email["fromAddress"], email["toAddress"],
                          email["summary"], email["html"]].join(" ").downcase
            Array(exclude_words).any? { |word| searchable.include?(word.downcase) }
          end

          def notify_match(email, rule)
            target = rule["notify_target"] || Config.default_notify_target
            channel = rule["notify_channel"] || Config.notify_channel

            unless target
              LOG.warn "[Zoho] No notify_target configured for rule '#{rule["label"]}' and no default set"
              return
            end

            message = format_notification(email, rule)
            agent = rule["notify_as"] || Config.notify_as

            LOG.info "[Zoho] Sending notification via #{channel} to #{target}"
            send_notification(:zoho_email, message, channel: channel, target: target, agent: agent)
          end

          def format_notification(email, rule)
            label = rule["label"] || "Zoho Mail"
            emoji = rule["emoji"] || "📧"
            parts = ["#{emoji} **#{label}**"]
            parts << "**Subject:** #{email["subject"]}" if email["subject"]
            parts << "**From:** #{email["fromAddress"]}" if email["fromAddress"]
            parts << "**To:** #{email["toAddress"]}" if email["toAddress"]

            body_text = extract_body_text(email, rule)
            parts << "```\n#{body_text}\n```" if body_text

            parts.join("\n")
          end

          private

          def fallback_rule
            fallback = Config.fallback
            return nil unless fallback && fallback["enabled"] != false

            { "label" => fallback["label"] || "Unmatched Email",
              "emoji" => fallback["emoji"] || "📬",
              "notify_target" => fallback["notify_target"],
              "notify_channel" => fallback["notify_channel"],
              "notify_as" => fallback["notify_as"] }
          end

          def extract_body_text(email, rule)
            body_text = email["summary"].to_s.strip
            if body_text.empty?
              raw_html = (email["html"] || email["content"] || email["body"] || "").to_s
              body_text = raw_html.gsub(/<[^>]+>/, " ").gsub(/&nbsp;/i, " ").gsub(/\s+/, " ").strip
            end

            body_text = MailApi.fetch_email_content(email["messageId"]).to_s if body_text.empty? && rule["show_body"] && email["messageId"]

            return nil if body_text.empty?

            max_len = rule["show_body"] ? 1800 : 500
            body_text = "#{body_text[0..max_len]}..." if body_text.length > max_len
            body_text
          end

          def dump_payload(email)
            zoho_debug_dir = File.join(ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac")), "tmp", "zoho", "payloads")
            FileUtils.mkdir_p(zoho_debug_dir)
            File.write(File.join(zoho_debug_dir, "#{Time.now.strftime("%Y%m%d-%H%M%S")}.json"), JSON.pretty_generate(email))
          rescue StandardError => e
            LOG.warn "[Zoho] Could not dump payload: #{e.message}"
          end
        end
      end
    end
  end
end
