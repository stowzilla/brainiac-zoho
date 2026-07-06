# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "openssl"
require "base64"
require "rack/utils"

# --- Stub core constants and functions that the plugin expects ---

TEST_BRAINIAC_DIR = Dir.mktmpdir("brainiac-zoho-test")

BRAINIAC_DIR = TEST_BRAINIAC_DIR unless defined?(BRAINIAC_DIR)
ENV["BRAINIAC_DIR"] = TEST_BRAINIAC_DIR

unless defined?(LOG)
  LOG = Class.new do
    def info(_msg) = nil
    def warn(_msg) = nil
    def error(_msg) = nil
    def debug(_msg) = nil
    def debug? = false
  end.new
end

AI_AGENT_NAME = "Sherlock" unless defined?(AI_AGENT_NAME)

# Stub core Brainiac module with hooks
module Brainiac
  @hooks = Hash.new { |h, k| h[k] = [] }
  @channel_prompts = {}
  @channel_pre_post_checks = {}

  class << self
    def on(event, &block) = @hooks[event] << block

    def emit(event, **ctx)
      @hooks[event].filter_map do |h|
        h.call(ctx)
      rescue StandardError
        nil
      end
    end

    def register_channel_prompt(channel, prompt, pre_post_check: nil)
      @channel_prompts[channel] = prompt
      @channel_pre_post_checks[channel] = pre_post_check if pre_post_check
    end
    attr_reader :hooks, :channel_prompts, :channel_pre_post_checks

    def reset_hooks!
      @hooks = Hash.new { |h, k| h[k] = [] }
      @channel_prompts = {}
      @channel_pre_post_checks = {}
    end
  end

  module Plugins; end
end

# Stub core constants
AGENT_REGISTRY = {
  "sherlock" => { "display_name" => "Sherlock", "local" => true, "env" => {} },
  "merlin" => { "display_name" => "Merlin", "local" => true, "env" => {} }
}.freeze

PROJECTS = {
  "marketplace" => { "repo_path" => "/tmp/test-repo", "tags" => %w[marketplace mp] }
}.freeze

DEFAULT_PROJECT = {
  "agent_cli" => "kiro-cli",
  "agent_cli_args" => "chat --trust-all-tools --no-interactive"
}.freeze

# Stub core functions
def agent_env_for(_name) = {}
def default_project_key = "marketplace"
def resolve_project_cli_config(_config) = DEFAULT_PROJECT
def send_notification(_type, _msg, **) = nil

# Write zoho.json for tests
zoho_config = {
  "hook_secret" => "test-zoho-secret",
  "default_notify_target" => "1234567890", "notify_channel" => "discord",
  "notify_as" => "merlin",
  "rules" => [
    { "label" => "Item Sold", "enabled" => true, "subject_contains" => "sold", "emoji" => "💰",
      "from_contains" => "", "to_contains" => "", "body_contains" => "", "exclude_words" => [] },
    { "label" => "Disabled Rule", "enabled" => false, "subject_contains" => "test" }
  ],
  "fallback" => { "enabled" => true, "label" => "Unmatched Email", "emoji" => "📬", "exclude_words" => ["unsubscribe"] }
}
File.write(File.join(TEST_BRAINIAC_DIR, "zoho.json"), JSON.generate(zoho_config))

# Create required dirs
FileUtils.mkdir_p(File.join(TEST_BRAINIAC_DIR, "tmp", "zoho", "payloads"))
FileUtils.mkdir_p(File.join(TEST_BRAINIAC_DIR, "tmp", "zoho", "triage"))

require_relative "../lib/brainiac_zoho"

# Load config
Brainiac::Plugins::Zoho::Config.load!

# Cleanup
Minitest.after_run { FileUtils.rm_rf(TEST_BRAINIAC_DIR) }
