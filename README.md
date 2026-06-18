# inliner

A Neovim plugin for AI-powered inline code editing with support for multiple LLM providers (OpenAI, Anthropic, xAI, GitHub Copilot, OpenRouter, Cerebras).

Select code in visual mode, press `<leader>ae`, and the AI edits it inline.

## Features

- Select code in visual mode and apply AI edits inline
- No confirmation dialogs — seamless editing experience
- Customizable system prompts, provider, and model
- Configurable keybindings
- Built with Lua for optimal performance
- **Diff mode**: Review AI changes as git-style conflict markers before applying

## Prerequisites

- Neovim >= 0.8.0
- API key for at least one supported provider
- For GitHub Copilot: [copilot.lua](https://github.com/zbirenbaum/copilot.lua) installed and authenticated

**Optional:** [Snacks.nvim](https://github.com/folke/snacks.nvim) — enhanced input UI with icons and custom styling.

## Installation

### lazy.nvim

```lua
{
  "inliner",
  event = "VeryLazy",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "inliner",
  config = function()
    require("inliner").setup()
  end,
}
```

## Quick Start

1. Set your API key(s) in your shell profile:
   ```bash
   export OPENAI_API_KEY="your-openai-api-key"
   export ANTHROPIC_API_KEY="your-anthropic-api-key"
   export XAI_API_KEY="your-xai-api-key"
   export OPENROUTER_API_KEY="your-openrouter-api-key"
   export CEREBRAS_API_KEY="your-cerebras-api-key"
   ```
2. Select code in visual mode (`v`, `V`, or `Ctrl-v`)
3. Press `<leader>ae` and enter your instruction
4. The AI applies changes inline

## Configuration

### Provider and Model

Configure your LLM provider and model in `setup()`:

```lua
require("inliner").setup({
  llm = {
    provider = "openai",        -- "openai", "anthropic", "xai", "copilot", "openrouter", "cerebras", "gemini"
    model = "gpt-4o-mini",      -- Model name (optional — provider default used if nil)
  },
})
```

See `:checkhealth inliner` to verify your setup is ready.

### Diff Mode

```lua
require("inliner").setup({
  diff_mode = true,
})
```

### All Options

```lua
{
  system_prompt = string,       -- Custom system prompt for the LLM
  keys = table,                 -- Array of keybindings
  llm = {
    provider = "openai",        -- Provider to use
    model = nil,                -- Model name (optional)
    timeout = 30000,            -- Request timeout in ms
    max_output_tokens = nil,
  },
  codesearch = {
    enabled = true,             -- Enable/disable codebase search for question/explain
    max_results = 15,           -- Max search results per query
    context_lines = 3,          -- Lines of context around each match
    max_keywords = 5,           -- Max keywords extracted from selection
  },
  diff_mode = false,
  input = {
    prompt = "AI Edit: ",
  },
  debug = false,
  log_file = vim.fn.stdpath("state") .. "/inliner.log",
}
```

## Development

```bash
make test        # Run tests
make format      # Format Lua
make lint        # Lint Lua
```

## License

MIT
