local mock_config = {
  input = {
    prompt = "AI Edit: ",
    icon = "󱚣",
  },
}

local function with_mock_popup(mock)
  package.loaded["inliner.popup"] = mock
  package.loaded["inliner.input"] = nil
  return require("inliner.input")
end

describe("input", function()
  describe("get_instruction", function()
    after_each(function()
      package.loaded["inliner.popup"] = nil
      package.loaded["inliner.input"] = nil
    end)

    it("should call callback with user input", function()
      local result = nil
      local called = false

      local input = with_mock_popup({
        show = function(opts, submit_cb, cancel_cb)
          assert.are.equal("󱚣", opts.icon)
          assert.are.equal("AI Edit", opts.title)
          assert.are.equal("AI Edit: ", opts.prompt)
          submit_cb("test instruction")
        end,
      })

      input.get_instruction(mock_config, function(instruction)
        called = true
        result = instruction
      end)

      assert.is_true(called)
      assert.are.equal("test instruction", result)
    end)

    it("should call cancel_callback when input is empty", function()
      local cancel_called = false

      local input = with_mock_popup({
        show = function(opts, submit_cb, cancel_cb)
          submit_cb("")
        end,
      })

      input.get_instruction(mock_config, function() end, function()
        cancel_called = true
      end)

      assert.is_true(cancel_called)
    end)

    it("should call cancel_callback on cancel", function()
      local cancel_called = false

      local input = with_mock_popup({
        show = function(opts, submit_cb, cancel_cb)
          cancel_cb()
        end,
      })

      input.get_instruction(mock_config, function() end, function()
        cancel_called = true
      end)

      assert.is_true(cancel_called)
    end)

    it("should handle multi-word instructions", function()
      local result = nil

      local input = with_mock_popup({
        show = function(opts, submit_cb, cancel_cb)
          submit_cb("add error handling with try catch")
        end,
      })

      input.get_instruction(mock_config, function(instruction)
        result = instruction
      end)

      assert.are.equal("add error handling with try catch", result)
    end)

    it("should preserve whitespace in instructions", function()
      local result = nil

      local input = with_mock_popup({
        show = function(opts, submit_cb, cancel_cb)
          submit_cb("  leading and trailing spaces  ")
        end,
      })

      input.get_instruction(mock_config, function(instruction)
        result = instruction
      end)

      assert.are.equal("  leading and trailing spaces  ", result)
    end)

    it("should use custom input options from config", function()
      local custom_config = {
        input = {
          prompt = "Custom Prompt: ",
          icon = "󱚣",
        },
      }

      local input = with_mock_popup({
        show = function(opts, submit_cb, cancel_cb)
          assert.are.equal("󱚣", opts.icon)
          assert.are.equal("Custom Prompt", opts.title)
          assert.are.equal("Custom Prompt: ", opts.prompt)
          submit_cb("test")
        end,
      })

      input.get_instruction(custom_config, function() end)
    end)
  end)
end)
