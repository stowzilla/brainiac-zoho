# frozen_string_literal: true

require_relative "test_helper"

class TestZohoPlugin < Minitest::Test
  def test_register_method_exists
    assert_respond_to Brainiac::Plugins::Zoho, :register
  end

  def test_version_format
    version = Brainiac::Plugins::Zoho::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, version)
  end

  def test_config_loads
    config = Brainiac::Plugins::Zoho::Config.config
    assert_kind_of Hash, config
    assert_equal "test-zoho-secret", config["hook_secret"]
  end

  def test_hook_secret
    assert_equal "test-zoho-secret", Brainiac::Plugins::Zoho::Config.hook_secret
  end

  def test_configured
    assert Brainiac::Plugins::Zoho.configured?
  end

  def test_help_text
    assert_includes Brainiac::Plugins::Zoho.help_text, "brainiac zoho"
  end

  def test_completions
    completions = Brainiac::Plugins::Zoho.completions
    assert_includes completions, "setup"
    assert_includes completions, "config"
    assert_includes completions, "auth"
  end

  def test_rule_matches_subject
    rule = { "subject_contains" => "sold", "from_contains" => "", "to_contains" => "", "body_contains" => "" }
    email = { "subject" => "Item sold!", "fromAddress" => "a@b.com", "toAddress" => "c@d.com", "summary" => "" }
    assert Brainiac::Plugins::Zoho::Handler.rule_matches?(rule, email)
  end

  def test_rule_does_not_match
    rule = { "subject_contains" => "sold", "from_contains" => "", "to_contains" => "", "body_contains" => "" }
    email = { "subject" => "Hello world", "fromAddress" => "a@b.com", "toAddress" => "c@d.com", "summary" => "" }
    refute Brainiac::Plugins::Zoho::Handler.rule_matches?(rule, email)
  end

  def test_disabled_rule_does_not_match
    rule = { "enabled" => false, "subject_contains" => "test" }
    email = { "subject" => "test email" }
    refute Brainiac::Plugins::Zoho::Handler.rule_matches?(rule, email)
  end

  def test_email_excluded
    email = { "subject" => "Unsubscribe", "fromAddress" => "", "toAddress" => "", "summary" => "", "html" => "" }
    assert Brainiac::Plugins::Zoho::Handler.email_excluded?(email, ["unsubscribe"])
  end

  def test_email_not_excluded
    email = { "subject" => "Normal email", "fromAddress" => "", "toAddress" => "", "summary" => "", "html" => "" }
    refute Brainiac::Plugins::Zoho::Handler.email_excluded?(email, ["unsubscribe"])
  end

  def test_match_rule_finds_matching
    email = { "subject" => "Item sold today", "fromAddress" => "a@b.com", "toAddress" => "c@d.com",
              "summary" => "", "html" => "" }
    rule = Brainiac::Plugins::Zoho::Handler.match_rule(email)
    assert_equal "Item Sold", rule["label"]
  end

  def test_match_rule_fallback
    email = { "subject" => "Random email", "fromAddress" => "a@b.com", "toAddress" => "c@d.com",
              "summary" => "", "html" => "" }
    rule = Brainiac::Plugins::Zoho::Handler.match_rule(email)
    assert_equal "Unmatched Email", rule["label"]
  end

  def test_match_rule_fallback_excluded
    email = { "subject" => "Please unsubscribe me", "fromAddress" => "a@b.com", "toAddress" => "c@d.com",
              "summary" => "", "html" => "" }
    rule = Brainiac::Plugins::Zoho::Handler.match_rule(email)
    assert_nil rule
  end

  def test_format_notification
    rule = { "label" => "Test", "emoji" => "🧪" }
    email = { "subject" => "Hello", "fromAddress" => "a@b.com", "toAddress" => "c@d.com", "summary" => "body text" }
    result = Brainiac::Plugins::Zoho::Handler.format_notification(email, rule)
    assert_includes result, "🧪 **Test**"
    assert_includes result, "Hello"
    assert_includes result, "a@b.com"
  end

  def test_triage_prompt_template_exists
    assert_kind_of String, Brainiac::Plugins::Zoho::Triage::PROMPT_TEMPLATE
    assert_includes Brainiac::Plugins::Zoho::Triage::PROMPT_TEMPLATE, "{{SUBJECT}}"
  end
end
