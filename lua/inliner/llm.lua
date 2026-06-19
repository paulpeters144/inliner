local logger = require("inliner.logger")

local M = {}

M.PROVIDER_API_KEYS = {
  openai = "OPENAI_API_KEY",
  anthropic = "ANTHROPIC_API_KEY",
  xai = "XAI_API_KEY",
  openrouter = "OPENROUTER_API_KEY",
  copilot = "COPILOT_TOKEN",
  cerebras = "CEREBRAS_API_KEY",
  gemini = "GEMINI_API_KEY",
}

local DEFAULT_MODELS = {
  openai = "gpt-4o-mini",
  anthropic = "claude-3-5-sonnet-20241022",
  xai = "grok-4-fast-non-reasoning",
  openrouter = "anthropic/claude-3.5-sonnet",
  copilot = "gpt-4o",
  cerebras = "qwen-3-235b-a22b-instruct-2507",
  gemini = "gemini-3.1-flash-lite",
}

local DEFAULT_ENDPOINTS = {
  openai = "https://api.openai.com/v1",
  anthropic = "https://api.anthropic.com/v1",
  xai = "https://api.x.ai/v1",
  openrouter = "https://openrouter.ai/api/v1",
  cerebras = "https://api.cerebras.ai/v1",
  gemini = "https://generativelanguage.googleapis.com/v1beta/openai",
}

local COPILOT_ENDPOINT = "https://api.githubcopilot.com/chat/completions"
local COPILOT_TOKEN_URL = "https://api.github.com/copilot_internal/v2/token"

local copilot_cache = {
  bearer_token = nil,
  expires_at = 0,
}

function M.get_api_key(provider)
  if provider == "copilot" then
    return ""
  end
  local env_var = M.PROVIDER_API_KEYS[provider]
  if not env_var then
    return nil
  end
  return vim.fn.environ()[env_var] or os.getenv(env_var)
end

local function http_request(url, opts, callback)
  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--request",
    opts.method or "GET",
    "--location",
  }

  if opts.timeout then
    table.insert(args, "--max-time")
    table.insert(args, tostring(math.ceil(opts.timeout / 1000)))
  end

  for key, value in pairs(opts.headers or {}) do
    table.insert(args, "--header")
    table.insert(args, key .. ": " .. value)
  end

  if opts.body then
    table.insert(args, "--data-binary")
    table.insert(args, "@-")
  end

  table.insert(args, url)

  local system_opts = {}
  if opts.body then
    system_opts.stdin = opts.body
    logger.debug("llm", "Request body: " .. opts.body)
  end

  logger.debug("llm", "HTTP " .. (opts.method or "GET") .. " " .. url)

  vim.system(args, system_opts, function(res)
    if res.signal and res.signal ~= 0 then
      logger.error("llm", "Request terminated by signal " .. res.signal)
      callback(nil, "Request was terminated (signal " .. res.signal .. ")")
      return
    end
    if res.code ~= 0 then
      local err = (res.stderr or "") ~= "" and res.stderr or ("curl exited with code " .. res.code)
      logger.error("llm", "Request failed: " .. err)
      callback(nil, err)
      return
    end
    callback(res.stdout or "", nil)
  end)
end

local function parse_json(str)
  local ok, result = pcall(vim.json.decode, str)
  if ok then
    return result
  end
  return nil
end

function M.strip_markdown(text)
  text = vim.trim(text)
  local fence_open = text:match("^```[%w%+%#%-%.]*\n")
  if fence_open then
    local inner = text:sub(#fence_open + 1)
    local sidx = inner:find("\n```")
    if sidx then
      return inner:sub(1, sidx - 1)
    end
  end
  return text
end

function M.extract_copilot_token()
  local home = vim.fn.expand("$HOME")
  local config_path = home .. "/.config/github-copilot/apps.json"

  if vim.fn.has("win32") == 1 then
    local appdata = os.getenv("APPDATA")
    if not appdata then
      return nil, "APPDATA environment variable is not set. Cannot find Copilot config."
    end
    config_path = appdata .. "/GitHub Copilot/apps.json"
  end

  if vim.fn.filereadable(config_path) == 0 then
    return nil,
      "Copilot not authenticated. Install and authenticate copilot.lua first. Expected config at: "
        .. config_path
        .. ". Run `:checkhealth inliner` for details."
  end

  local ok, content = pcall(vim.fn.readfile, config_path)
  if not ok or not content then
    return nil, "Could not read Copilot config file: " .. config_path
  end

  local config = parse_json(table.concat(content, "\n"))
  if not config then
    return nil, "Copilot config file is corrupted (invalid JSON): " .. config_path
  end

  local github_key = nil
  for key, _ in pairs(config) do
    if key:find("^github%.com") then
      github_key = key
      break
    end
  end

  if not github_key then
    return nil, "Copilot config missing github.com entry"
  end

  local token = config[github_key] and config[github_key].oauth_token
  if not token or token == "" then
    return nil, "Copilot config missing oauth_token"
  end

  logger.debug("copilot", "Successfully extracted Copilot token")
  return token, nil
end

local function exchange_copilot_token(oauth_token, callback)
  if copilot_cache.bearer_token and copilot_cache.expires_at > vim.loop.now() then
    callback(copilot_cache.bearer_token, nil)
    return
  end

  local headers = {
    ["Content-Type"] = "application/json",
    authorization = "token " .. oauth_token,
    ["editor-version"] = "vscode/1.90.2",
    ["editor-plugin-version"] = "copilot-chat/0.17.2024062801",
    ["user-agent"] = "GitHubCopilotChat/0.17.2024062801",
  }

  http_request(COPILOT_TOKEN_URL, { method = "GET", headers = headers, timeout = 10000 }, function(body, err)
    if err then
      callback(nil, "Failed to exchange Copilot token: " .. err)
      return
    end

    local data = parse_json(body)
    if not data then
      callback(nil, "Failed to parse Copilot token response")
      return
    end

    if data.token then
      copilot_cache.bearer_token = data.token
      copilot_cache.expires_at = data.expires_at or (vim.loop.now() + 1500)
      logger.debug("copilot", "Exchanged OAuth token for bearer token")
      callback(data.token, nil)
    else
      callback(nil, "Copilot token response missing 'token' field")
    end
  end)
end

local function check_curl()
  if vim.fn.executable("curl") == 0 then
    return false
  end
  return true
end

local function provider_call(provider_name, params, callback)
  if not check_curl() then
    callback(nil, "curl is not available on PATH. Install curl to make API requests.")
    return
  end

  local model = params.model or DEFAULT_MODELS[provider_name]
  local api_key = M.get_api_key(provider_name)
  local system_prompt = params.systemPrompt
    or "You are a code editing assistant. Apply the requested changes and return only the modified code. No explanations."
  local max_tokens = params.maxOutputTokens or 4096
  local timeout = params.timeout or 30000

  if
    provider_name == "openai"
    or provider_name == "xai"
    or provider_name == "openrouter"
    or provider_name == "cerebras"
    or provider_name == "gemini"
  then
    local endpoint = params.baseURL or DEFAULT_ENDPOINTS[provider_name]
    local url = endpoint .. "/chat/completions"

    if not api_key then
      callback(nil, M.PROVIDER_API_KEYS[provider_name] .. " is not set. Run `:checkhealth inliner` for setup help.")
      return
    end

    local chat_messages = params.messages
    if not chat_messages then
      local user_content = "Instruction: " .. params.instruction
      if params.file_path and params.file_path ~= "" then
        user_content = user_content .. "\n\n<file_path>" .. params.file_path .. "</file_path>"
      end
      if params.context then
        user_content = user_content .. "\n\n" .. params.context
      elseif params.code then
        user_content = user_content .. "\n\n<selection>\n" .. params.code .. "\n</selection>"
      end
      chat_messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = user_content },
      }
    end
    local payload = {
      model = model,
      messages = chat_messages,
      max_tokens = max_tokens,
    }
    logger.debug("llm", "Prompt sent to LLM", payload)
    local body = vim.json.encode(payload)

    local headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    }

    http_request(url, { method = "POST", headers = headers, body = body, timeout = timeout }, function(resp, err)
      if err then
        callback(nil, err)
        return
      end
      local data = parse_json(resp)
      if not data then
        callback(nil, "Failed to parse API response. Check your network and API key. Run `:checkhealth inliner`.")
        return
      end
      if data.error then
        local msg = type(data.error) == "string" and data.error or (data.error.message or tostring(data.error))
        callback(
          nil,
          "API error (" .. provider_name .. "): " .. msg .. ". Run `:checkhealth inliner` if this persists."
        )
        return
      end
      if data.choices and #data.choices > 0 and data.choices[1].message and data.choices[1].message.content then
        local result = data.choices[1].message.content
        if params.strip_markdown ~= false then
          result = M.strip_markdown(result)
        end
        callback(result, nil)
      else
        logger.debug("llm", "Unexpected response: " .. (resp or "nil"))
        callback(nil, "Unexpected response from " .. provider_name .. ". Run `:checkhealth inliner`.")
      end
    end)
  elseif provider_name == "anthropic" then
    local url = (params.baseURL or DEFAULT_ENDPOINTS.anthropic) .. "/messages"

    if not api_key then
      callback(nil, "ANTHROPIC_API_KEY is not set. Run `:checkhealth inliner` for setup help.")
      return
    end

    local system_content = system_prompt
    local chat_messages = params.messages
    if not chat_messages then
      local user_content = "Instruction: " .. params.instruction
      if params.file_path and params.file_path ~= "" then
        user_content = user_content .. "\n\n<file_path>" .. params.file_path .. "</file_path>"
      end
      if params.context then
        user_content = user_content .. "\n\n" .. params.context
      elseif params.code then
        user_content = user_content .. "\n\n<selection>\n" .. params.code .. "\n</selection>"
      end
      chat_messages = {
        { role = "user", content = user_content },
      }
    end
    if params.messages then
      local filtered = {}
      for _, msg in ipairs(params.messages) do
        if msg.role == "system" then
          system_content = msg.content
        else
          table.insert(filtered, msg)
        end
      end
      chat_messages = filtered
    end
    local payload = {
      model = model,
      system = system_content,
      messages = chat_messages,
      max_tokens = max_tokens,
    }
    logger.debug("llm", "Prompt sent to LLM", payload)
    local body = vim.json.encode(payload)

    local headers = {
      ["Content-Type"] = "application/json",
      ["x-api-key"] = api_key,
      ["anthropic-version"] = "2023-06-01",
    }

    http_request(url, { method = "POST", headers = headers, body = body, timeout = timeout }, function(resp, err)
      if err then
        callback(nil, err)
        return
      end
      local data = parse_json(resp)
      if not data then
        callback(nil, "Failed to parse API response. Check your network and API key. Run `:checkhealth inliner`.")
        return
      end
      if data.error then
        local msg = type(data.error) == "string" and data.error or (data.error.message or tostring(data.error))
        callback(nil, "API error (anthropic): " .. msg .. ". Run `:checkhealth inliner` if this persists.")
        return
      end
      if data.content and #data.content > 0 and data.content[1].text then
        local result = data.content[1].text
        if params.strip_markdown ~= false then
          result = M.strip_markdown(result)
        end
        callback(result, nil)
      else
        callback(nil, "Unexpected response from anthropic. Run `:checkhealth inliner`.")
      end
    end)
  elseif provider_name == "copilot" then
    local oauth_token, err = M.extract_copilot_token()
    if not oauth_token then
      callback(nil, err)
      return
    end

    exchange_copilot_token(oauth_token, function(bearer_token, err)
      if err then
        callback(nil, err)
        return
      end

      local chat_messages = params.messages
      if not chat_messages then
        local user_content = "Instruction: " .. params.instruction
        if params.file_path and params.file_path ~= "" then
          user_content = user_content .. "\n\n<file_path>" .. params.file_path .. "</file_path>"
        end
        if params.context then
          user_content = user_content .. "\n\n" .. params.context
        elseif params.code then
          user_content = user_content .. "\n\n<selection>\n" .. params.code .. "\n</selection>"
        end
        chat_messages = {
          { role = "system", content = system_prompt },
          { role = "user", content = user_content },
        }
      end
    local payload = {
      model = model,
      messages = chat_messages,
      max_tokens = max_tokens,
    }
    logger.debug("llm", "Prompt sent to LLM", payload)
    local body = vim.json.encode(payload)

    local headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. bearer_token,
      ["editor-version"] = "vscode/1.90.2",
    }

      http_request(
        COPILOT_ENDPOINT,
        { method = "POST", headers = headers, body = body, timeout = timeout },
        function(resp, err)
          if err then
            callback(nil, err)
            return
          end
          local data = parse_json(resp)
          if not data then
            callback(nil, "Failed to parse Copilot response. Run `:checkhealth inliner` for help.")
            return
          end
          if data.error then
            local msg = type(data.error) == "string" and data.error or (data.error.message or tostring(data.error))
            callback(nil, "Copilot error: " .. msg .. ". Run `:checkhealth inliner` if this persists.")
            return
          end
          if data.choices and #data.choices > 0 and data.choices[1].message and data.choices[1].message.content then
            local result = data.choices[1].message.content
            if params.strip_markdown ~= false then
              result = M.strip_markdown(result)
            end
            callback(result, nil)
          else
            callback(nil, "Unexpected response from Copilot. Run `:checkhealth inliner`.")
          end
        end
      )
    end)
  else
    callback(nil, "Unknown provider: " .. provider_name)
  end
end

function M.request_edit(params, callback)
  local provider_name = params.provider or "openai"
  logger.debug("llm", "Starting edit with provider: " .. provider_name)

  provider_call(provider_name, params, function(result, err)
    if err then
      logger.error("llm", "Edit failed: " .. err)
      callback(nil, err)
    else
      logger.info("llm", "Edit completed successfully")
      callback(result, nil)
    end
  end)
end

function M.request_chat(params, callback)
  params.strip_markdown = false
  local provider_name = params.provider or "openai"
  logger.debug("llm", "Starting chat with provider: " .. provider_name)

  provider_call(provider_name, params, function(result, err)
    if err then
      logger.error("llm", "Chat failed: " .. err)
      callback(nil, err)
    else
      logger.info("llm", "Chat completed successfully")
      callback(result, nil)
    end
  end)
end

return M
