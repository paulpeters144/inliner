local M = {}

local PROVIDER_API_KEYS = require("inliner.llm").PROVIDER_API_KEYS
  or {
    openai = "OPENAI_API_KEY",
    anthropic = "ANTHROPIC_API_KEY",
    xai = "XAI_API_KEY",
    openrouter = "OPENROUTER_API_KEY",
    copilot = "COPILOT_TOKEN",
    cerebras = "CEREBRAS_API_KEY",
    gemini = "GEMINI_API_KEY",
  }

function M.check()
  vim.health.start("inliner")

  if not vim.g.loaded_inliner then
    vim.health.error("Plugin is not loaded. Is the plugin installed and sourced?")
    return
  end
  vim.health.ok("Plugin is loaded")

  local ok, inliner = pcall(require, "inliner")
  if not ok then
    vim.health.error("Failed to load inliner module: " .. tostring(inliner))
    return
  end

  local config = inliner.config
  if not config then
    vim.health.warn("setup() has not been called yet. Using default configuration.")
    config = {}
  else
    vim.health.ok("setup() has been called")
  end

  local all_ok = true

  local provider = config.llm and config.llm.provider or "openai"
  local model = config.llm and config.llm.model or "default"
  vim.health.info(string.format("Provider: %s", provider))
  vim.health.info(string.format("Model: %s", model))

  local env_var = PROVIDER_API_KEYS[provider]
  if provider == "copilot" then
    local token, err = inliner.llm.extract_copilot_token()
    if token then
      vim.health.ok("Copilot OAuth token found")
    else
      vim.health.error("Copilot: " .. (err or "no token found"))
      all_ok = false
    end
  elseif env_var then
    local val = vim.fn.environ()[env_var] or os.getenv(env_var)
    if val then
      vim.health.ok(string.format("%s is set for provider '%s'", env_var, provider))
    else
      vim.health.error(string.format("%s is not set — provider '%s' will fail", env_var, provider))
      all_ok = false
    end
  else
    vim.health.error(string.format("Unknown provider '%s'", provider))
    all_ok = false
  end

  local curl_ok = vim.fn.executable("curl") == 1
  if curl_ok then
    vim.health.ok("curl is available")
  else
    vim.health.error("curl is not found on PATH — HTTP requests will fail")
    all_ok = false
  end

  if config.debug then
    local log_file = config.log_file
    if log_file then
      vim.health.info(string.format("Debug logging to: %s", log_file))
    end
  else
    vim.health.info("Debug logging is disabled (set debug = true in setup to enable)")
  end

  if all_ok then
    vim.health.ok("inliner is ready to use")
  else
    vim.health.warn("inliner is not fully configured — fix the errors above")
  end
end

return M
