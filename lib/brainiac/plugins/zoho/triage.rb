# frozen_string_literal: true

module Brainiac
  module Plugins
    module Zoho
      module Triage
        PROMPT_TEMPLATE = <<~PROMPT
          You are triaging a support email. Decide whether this email needs a card or not.

          ## Email
          **From:** {{FROM}}
          **To:** {{TO}}
          **Subject:** {{SUBJECT}}
          **Body:**
          ```
          {{BODY}}
          ```

          ## Decision Criteria
          **Needs a card** (something is broken, a bug report, a feature request, a workflow issue):
          - Create a card with a clear title summarizing the issue
          - Tag with `support` plus a project tag if you can identify the relevant project
          - Assign to the appropriate agent

          **Does NOT need a card** (account questions, password resets, general inquiries, spam, marketing):
          - Just explain why briefly

          **Borderline** (you're not sure):
          - Mark as borderline and explain why — a human will decide

          ## Project Tags (use the tag name, not the ID)
          {{PROJECT_TAGS}}

          ## Agent Assignment
          {{AGENT_ASSIGNMENT}}

          ## Response Format
          Write ONLY valid JSON to stdout (no markdown, no explanation outside the JSON):

          For "needs a card":
          ```json
          {
            "decision": "create_card",
            "title": "Brief descriptive title for the card",
            "description": "HTML description with relevant details from the email",
            "project_tag": "project-tag-name or null",
            "assign_to": "agent-name from the assignment rules above"
          }
          ```

          For "does not need a card":
          ```json
          {
            "decision": "skip",
            "reason": "Brief explanation of why no card is needed"
          }
          ```

          For "borderline":
          ```json
          {
            "decision": "borderline",
            "reason": "Why you're unsure — what makes this ambiguous"
          }
          ```
        PROMPT

        class << self
          def dispatch(email, rule)
            agent_name = rule["dispatch_agent"]
            timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
            triage_dir = File.join(ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac")), "tmp", "zoho", "triage")
            FileUtils.mkdir_p(triage_dir)

            response_file = File.join(triage_dir, "triage-#{timestamp}.json")
            log_file = File.join(triage_dir, "triage-#{timestamp}.log")
            prompt_file = write_prompt(email, response_file, timestamp, triage_dir)

            agent_key = agent_name.downcase.gsub(/[^a-z0-9-]/, "-")
            project_config = default_project_config
            resolved = resolve_project_cli_config(project_config || {})

            cmd = [resolved["agent_cli"]]
            cmd.push("--agent", agent_key)
            cmd.concat(resolved["agent_cli_args"].split)

            spawn_env = {}
            agent_env = agent_env_for(agent_name)
            spawn_env.merge!(agent_env) unless agent_env.empty?

            work_dir = project_config ? project_config["repo_path"] : Dir.pwd

            LOG.info "[Zoho:Triage] Dispatching #{agent_name} for: #{email["subject"]}"
            LOG.info "[Zoho:Triage] Command: #{cmd.join(" ")}"

            pid = spawn(spawn_env, *cmd,
                        chdir: work_dir, in: prompt_file,
                        out: [log_file, "w"], err: %i[child out])

            monitor(pid, response_file, log_file, prompt_file, email, rule)
            pid
          end

          private

          def default_project_config
            key = default_project_key
            key ? PROJECTS[key] : PROJECTS.values.first
          end

          def write_prompt(email, response_file, timestamp, triage_dir)
            body = (email["summary"] || email["html"] || "").to_s.gsub(/\s+/, " ").strip
            body = body[0..2000] if body.length > 2000

            prompt = PROMPT_TEMPLATE
                     .gsub("{{FROM}}", email["fromAddress"].to_s)
                     .gsub("{{TO}}", email["toAddress"].to_s)
                     .gsub("{{SUBJECT}}", email["subject"].to_s)
                     .gsub("{{BODY}}", body)
                     .gsub("{{PROJECT_TAGS}}", Config.triage_project_tags)
                     .gsub("{{AGENT_ASSIGNMENT}}", Config.triage_agent_assignment)
            prompt += "\n\nWrite your JSON response to: #{response_file}\n"

            prompt_file = File.join(triage_dir, "triage-prompt-#{timestamp}.md")
            File.write(prompt_file, prompt)
            prompt_file
          end

          def monitor(pid, response_file, log_file, prompt_file, email, rule)
            Thread.new do
              Process.wait(pid)
              LOG.info "[Zoho:Triage] Agent finished (exit: #{$CHILD_STATUS.exitstatus})"

              decision = read_response(response_file, log_file)
              if decision
                execute_decision(decision, email, rule)
              else
                LOG.warn "[Zoho:Triage] No valid decision from agent — falling back to notification"
                Handler.notify_match(email, rule)
              end

              Thread.new do
                sleep 300
                FileUtils.rm_f(prompt_file)
              end
            end
          end

          def read_response(response_file, log_file)
            if File.exist?(response_file) && !File.empty?(response_file)
              content = File.read(response_file).strip
              return parse_json(content)
            end

            if File.exist?(log_file)
              log_content = File.read(log_file)
              if (match = log_content.match(/\{[^{}]*"decision"\s*:\s*"[^"]+?"[^{}]*\}/m))
                return parse_json(match[0])
              end
            end

            nil
          end

          def parse_json(content)
            content = content.gsub(/```json\s*/, "").gsub(/```\s*/, "").strip
            JSON.parse(content)
          rescue JSON::ParserError => e
            LOG.warn "[Zoho:Triage] Failed to parse response JSON: #{e.message}"
            nil
          end

          def execute_decision(decision, email, rule)
            channel_id = rule["notify_target"] || Config.default_notify_target
            notify_channel = rule["notify_channel"] || Config.notify_channel
            bot_name = rule["notify_as"] || Config.notify_as

            case decision["decision"]
            when "create_card"
              create_card(decision, email, channel_id, notify_channel, bot_name)
            when "skip"
              msg = "📧 **Support Email — No Card Needed**\n"
              msg += "**Subject:** #{email["subject"]}\n"
              msg += "**From:** #{email["fromAddress"]}\n"
              msg += "**Reason:** #{decision["reason"]}"
              send_notification(:zoho_triage, msg, channel: notify_channel, target: channel_id, agent: bot_name)
              LOG.info "[Zoho:Triage] Skipped card: #{decision["reason"]}"
            when "borderline"
              msg = "⚠️ **Support Email — Needs Human Decision**\n"
              msg += "**Subject:** #{email["subject"]}\n"
              msg += "**From:** #{email["fromAddress"]}\n"
              msg += "**Why borderline:** #{decision["reason"]}\n"
              summary = (email["summary"] || "").to_s[0..300]
              msg += "```\n#{summary}\n```" unless summary.empty?
              send_notification(:zoho_triage, msg, channel: notify_channel, target: channel_id, agent: bot_name)
              LOG.info "[Zoho:Triage] Borderline — posted for human decision"
            else
              LOG.warn "[Zoho:Triage] Unknown decision: #{decision["decision"]}"
              Handler.notify_match(email, rule)
            end
          end

          def create_card(decision, email, channel_id, notify_channel, bot_name)
            board_id = Config.triage_board_id
            unless board_id
              LOG.error "[Zoho:Triage] No triage_board_id configured in zoho.json"
              return
            end

            title = decision["title"] || email["subject"]
            description = decision["description"] || "<p>Support email from #{email["fromAddress"]}: #{email["subject"]}</p>"
            tags = ["support"]
            tags << decision["project_tag"] if decision["project_tag"]

            results = Brainiac.emit(:create_work_item,
                                    board_id: board_id, title: title,
                                    description: description, tags: tags,
                                    assign_to: decision["assign_to"])

            card_info = results.compact.first
            if card_info
              card_number = card_info[:number]
              card_url = card_info[:url]
              LOG.info "[Zoho:Triage] Created card ##{card_number}: #{title}"

              msg = "🎫 **Support Card Created: [##{card_number}](#{card_url})**\n"
              msg += "**Title:** #{title}\n"
              msg += "**Assigned to:** #{decision["assign_to"] || "unassigned"}\n"
              msg += "**Tags:** #{tags.join(", ")}\n"
              msg += "**From:** #{email["fromAddress"]}"
              send_notification(:zoho_triage, msg, channel: notify_channel, target: channel_id, agent: bot_name)
            else
              LOG.warn "[Zoho:Triage] No work item plugin handled card creation"
              Handler.notify_match(email, { "label" => "Support Email (no card plugin)", "emoji" => "⚠️" })
            end
          rescue StandardError => e
            LOG.error "[Zoho:Triage] Error creating card: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
            Handler.notify_match(email, { "label" => "Support Email", "emoji" => "🆘" })
          end
        end
      end
    end
  end
end
