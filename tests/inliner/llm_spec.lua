local llm = require("inliner.llm")

local function mock(t, k, v)
  t[k] = v
end

describe("llm", function()
  local original_environ
  local mock_environ_return = {}
  local mock_os_getenv_return

  before_each(function()
    original_environ = vim.fn.environ
    mock_environ_return = {}
    mock_os_getenv_return = nil
    mock(vim.fn, "environ", function() return mock_environ_return end)
    mock(os, "getenv", function(name)
      if type(mock_os_getenv_return) == "function" then
        return mock_os_getenv_return(name)
      end
      return mock_os_getenv_return
    end)
  end)

  after_each(function()
    mock(vim.fn, "environ", original_environ)
  end)

  describe("strip_markdown", function()
    it("should strip markdown code blocks with language", function()
      local input = "```javascript\nconst x = 1;\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("const x = 1;", result)
    end)

    it("should strip markdown code blocks without language", function()
      local input = "```\nconst x = 1;\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("const x = 1;", result)
    end)

    it("should return plain text unchanged", function()
      local input = "const x = 1;"
      local result = llm.strip_markdown(input)
      assert.are.equal("const x = 1;", result)
    end)

    it("should trim whitespace", function()
      local input = "  \n  const x = 1;  \n  "
      local result = llm.strip_markdown(input)
      assert.are.equal("const x = 1;", result)
    end)

    it("should strip markdown with multi-line code", function()
      local input = "```python\ndef hello():\n    print('world')\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("def hello():\n    print('world')", result)
    end)

    it("handles language with digits (python3)", function()
      local input = "```python3\nx = 1\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("x = 1", result)
    end)

    it("handles language with plus signs (c++)", function()
      local input = "```c++\nint x = 1;\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("int x = 1;", result)
    end)

    it("handles language with hash sign (c#)", function()
      local input = "```c#\nvar x = 1;\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("var x = 1;", result)
    end)

    it("handles language with dots (mermaid timeline)", function()
      local input = "```mermaid\ngraph TD\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("graph TD", result)
    end)

    it("handles missing closing fence", function()
      local input = "```lua\nlocal x = 1"
      local result = llm.strip_markdown(input)
      assert.are.equal("```lua\nlocal x = 1", result)
    end)

    it("handles content after closing fence", function()
      local input = "```lua\nlocal x = 1\n```\nremaining"
      local result = llm.strip_markdown(input)
      assert.are.equal("local x = 1", result)
    end)

    it("handles multiple fenced blocks", function()
      local input = "```lua\nlocal x = 1\n```\n```python\ny = 2\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("local x = 1", result)
    end)

    it("handles language without newline", function()
      local input = "```lua\ntest\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("test", result)
    end)

    it("handles empty fenced block", function()
      local input = "```\n\n```"
      local result = llm.strip_markdown(input)
      assert.are.equal("", result)
    end)
  end)

  describe("get_api_key", function()
    it("should return empty string for copilot", function()
      assert.are.equal("", llm.get_api_key("copilot"))
    end)

    it("should return nil for unknown provider", function()
      assert.is_nil(llm.get_api_key("unknown"))
    end)

    it("reads from vim.fn.environ()", function()
      mock_environ_return = { OPENAI_API_KEY = "sk-test123" }

      local key = llm.get_api_key("openai")

      assert.are.equal("sk-test123", key)
    end)

    it("falls back to os.getenv()", function()
      mock_os_getenv_return = function(name)
        if name == "ANTHROPIC_API_KEY" then
          return "sk-anthropic"
        end
        return nil
      end

      local key = llm.get_api_key("anthropic")

      assert.are.equal("sk-anthropic", key)
    end)

    it("returns nil for unset env var", function()
      local key = llm.get_api_key("openai")
      assert.is_nil(key)
    end)
  end)

  describe("extract_copilot_token", function()
    it("should return error when config file not found", function()
      mock_os_getenv_return = function(name)
        if name == "APPDATA" then return "C:\\Users\\test\\AppData\\Roaming" end
        return nil
      end
      local token, err = llm.extract_copilot_token()
      assert.is_nil(token)
      assert.is_true(err ~= nil and err:find("Copilot not authenticated") ~= nil)
    end)
  end)

  describe("parse_json", function()
    it("handles nil input", function()
      local ok, result = pcall(vim.json.decode, nil)
      assert.is_false(ok)
    end)

    it("handles malformed JSON", function()
      local ok, result = pcall(vim.json.decode, "{invalid")
      assert.is_false(ok)
    end)

    it("handles empty string", function()
      local ok, result = pcall(vim.json.decode, "")
      assert.is_false(ok)
    end)

    it("parses valid JSON", function()
      local ok, result = pcall(vim.json.decode, '{"key": "value"}')
      assert.is_true(ok)
      assert.are.equal("value", result.key)
    end)
  end)

  describe("provider_call", function()
    local original_executable
    local http_request_calls = {}

    before_each(function()
      http_request_calls = {}
      original_executable = vim.fn.executable
    end)

    after_each(function()
      mock(vim.fn, "executable", original_executable)
    end)

    it("fails when curl not available", function()
      mock(vim.fn, "executable", function()
        return 0
      end)

      llm.request_edit({
        provider = "openai",
        model = "gpt-4",
        instruction = "test",
        code = "test",
      }, function(result, err)
        assert.is_nil(result)
        assert.is_true(err:find("curl") ~= nil)
      end)
    end)
  end)
end)
