local health = require("inliner.health")

local function mock(t, k, v)
  t[k] = v
end

describe("health", function()
  local original_loaded_inliner
  local original_environ
  local original_os_getenv
  local original_executable
  local health_calls = {}

  local mock_environ_return = {}
  local mock_os_getenv_return = nil
  local mock_executable_return = function(_)
    return 1
  end

  local function capture_health()
    health_calls = {}
    vim.health = {
      start = function(name)
        table.insert(health_calls, { type = "start", name = name })
      end,
      ok = function(msg)
        table.insert(health_calls, { type = "ok", msg = msg })
      end,
      warn = function(msg)
        table.insert(health_calls, { type = "warn", msg = msg })
      end,
      error = function(msg)
        table.insert(health_calls, { type = "error", msg = msg })
      end,
      info = function(msg)
        table.insert(health_calls, { type = "info", msg = msg })
      end,
    }
  end

  before_each(function()
    original_loaded_inliner = vim.g.loaded_inliner
    original_environ = vim.fn.environ
    original_os_getenv = os.getenv
    original_executable = vim.fn.executable

    mock_environ_return = {}
    mock_os_getenv_return = nil
    mock_executable_return = function(_)
      return 1
    end

    mock(vim.fn, "environ", function()
      return mock_environ_return
    end)
    mock(os, "getenv", function()
      return mock_os_getenv_return
    end)
    mock(vim.fn, "executable", function(name)
      return mock_executable_return(name)
    end)

    capture_health()
  end)

  after_each(function()
    if original_loaded_inliner == nil then
      vim.g.loaded_inliner = nil
    else
      vim.g.loaded_inliner = original_loaded_inliner
    end
    mock(vim.fn, "environ", original_environ)
    mock(os, "getenv", original_os_getenv)
    mock(vim.fn, "executable", original_executable)
  end)

  it("reports error when plugin not loaded", function()
    vim.g.loaded_inliner = nil

    health.check()

    assert.are.equal(2, #health_calls)
    assert.are.equal("start", health_calls[1].type)
    assert.are.equal("error", health_calls[2].type)
  end)

  it("reports ok when plugin loaded", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.config = nil

    health.check()

    local found_ok = false
    for _, call in ipairs(health_calls) do
      if call.type == "ok" and call.msg:find("Plugin is loaded") then
        found_ok = true
        break
      end
    end
    assert.is_true(found_ok)
  end)

  it("reports warn when setup not called", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.config = nil

    health.check()

    local found_warn = false
    for _, call in ipairs(health_calls) do
      if call.type == "warn" and call.msg:find("setup%(%) has not been called") then
        found_warn = true
        break
      end
    end
    assert.is_true(found_warn)
  end)

  it("reports ok when setup called", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "openai" }, debug = false })

    health.check()

    local found_ok = false
    for _, call in ipairs(health_calls) do
      if call.type == "ok" and call.msg:find("setup%(%) has been called") then
        found_ok = true
        break
      end
    end
    assert.is_true(found_ok)
  end)

  it("reports provider and model info", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "anthropic", model = "claude-3-5-sonnet-20241022" }, debug = false })

    health.check()

    local found_provider = false
    local found_model = false
    for _, call in ipairs(health_calls) do
      if call.type == "info" and call.msg:find("Provider: anthropic") then
        found_provider = true
      end
      if call.type == "info" and call.msg:find("Model: claude%-3%-5%-sonnet%-20241022") then
        found_model = true
      end
    end
    assert.is_true(found_provider)
    assert.is_true(found_model)
  end)

  it("reports when API key is not set and provider will fail", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "openai" }, debug = false })

    health.check()

    local found_error = false
    for _, call in ipairs(health_calls) do
      if call.type == "error" and call.msg:find("OPENAI_API_KEY") then
        found_error = true
        break
      end
    end
    assert.is_true(found_error)
  end)

  it("reports curl availability", function()
    vim.g.loaded_inliner = true
    mock_executable_return = function(name)
      if name == "curl" then
        return 1
      end
      return 0
    end

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "openai" }, debug = false })

    health.check()

    local found_curl = false
    for _, call in ipairs(health_calls) do
      if call.type == "ok" and call.msg:find("curl is available") then
        found_curl = true
        break
      end
    end
    assert.is_true(found_curl)
  end)

  it("reports debug logging status", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "openai" }, debug = true })

    health.check()

    local found_debug = false
    for _, call in ipairs(health_calls) do
      if call.type == "info" and call.msg:find("Debug logging") then
        found_debug = true
        break
      end
    end
    assert.is_true(found_debug)
  end)

  it("reports warn summary when not fully configured", function()
    vim.g.loaded_inliner = true

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "openai" }, debug = false })

    health.check()

    local found_warn = false
    for _, call in ipairs(health_calls) do
      if call.type == "warn" and call.msg:find("not fully configured") then
        found_warn = true
        break
      end
    end
    assert.is_true(found_warn)
  end)

  it("reports ok summary when fully configured", function()
    vim.g.loaded_inliner = true
    mock_environ_return = { OPENAI_API_KEY = "sk-xxx" }

    package.loaded["inliner"] = nil
    local inliner = require("inliner")
    inliner.setup({ llm = { provider = "openai" }, debug = false })

    health.check()

    local found_ok = false
    for _, call in ipairs(health_calls) do
      if call.type == "ok" and call.msg:find("ready to use") then
        found_ok = true
        break
      end
    end
    assert.is_true(found_ok)
  end)
end)
