local selection = require("inliner.selection")
local input = require("inliner.input")
local llm = require("inliner.llm")
local replace = require("inliner.replace")
local logger = require("inliner.logger")
local spinner = require("inliner.spinner")
local diff = require("inliner.diff")

local M = {}
local setup_called = false

local SELECTION_NS = vim.api.nvim_create_namespace("inliner-selection")

M.config = {
  system_prompt = [[
  You are an expert code editor. Given selected code and an instruction,
  return only the modified code. Preserve the original style, structure,
  and indentation. Omit explanations and markdown formatting.
  ]],
  keys = {
    {
      "<leader>ae",
      function()
        require("inliner").edit()
      end,
      mode = "n",
      desc = "AI Edit Line",
    },
    {
      "<leader>ae",
      function()
        require("inliner").edit()
      end,
      mode = "v",
      desc = "AI Edit Selection",
    },
    {
      "<leader>aq",
      function()
        require("inliner").question()
      end,
      mode = "n",
      desc = "AI Question",
    },
    {
      "<leader>aq",
      function()
        require("inliner").question()
      end,
      mode = "v",
      desc = "AI Question Selection",
    },
    {
      "<leader>ax",
      function()
        require("inliner").explain()
      end,
      mode = "n",
      desc = "AI Explain Line",
    },
    {
      "<leader>ax",
      function()
        require("inliner").explain()
      end,
      mode = "v",
      desc = "AI Explain Selection",
    },

  },
  llm = {
    provider = "openai",
    model = nil,
    timeout = 30000,
    base_url = nil,
    max_output_tokens = nil,
  },
  input = {
    prompt = "AI Edit: ",
    icon = "󱚣",
    win = {
      title_pos = "left",
      relative = "cursor",
      row = -3,
      col = 0,
    },
  },
  question = {
    system_prompt = nil,
    input = {
      prompt = "Question: ",
    },
    max_width = 80,
  },
  diff_mode = false,
  diff = {
    autojump = true,
    mappings = {
      ours = "co",
      theirs = "ct",
      both = "cb",
      next = "]x",
      prev = "[x",
    },
    highlights = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  debug = false,
  log_file = vim.fn.stdpath("state") .. "/inliner.log",
  debug_max_log_size = 5000,
}

local function setup_highlight_groups()
  vim.api.nvim_set_hl(0, "InlinerCurrent", { link = M.config.diff.highlights.current, default = true })
  vim.api.nvim_set_hl(0, "InlinerIncoming", { link = M.config.diff.highlights.incoming, default = true })
end

local VALID_PROVIDERS = { "openai", "anthropic", "xai", "openrouter", "cerebras", "gemini", "copilot" }
local VALID_PROVIDER_MAP = {}
for _, name in ipairs(VALID_PROVIDERS) do
  VALID_PROVIDER_MAP[name] = true
end

local function detect_default_provider()
  for _, name in ipairs(VALID_PROVIDERS) do
    local key = llm.get_api_key(name)
    if key and key ~= "" then
      return name
    end
  end
  return "openai"
end

function M.setup(opts)
  opts = opts or {}

  if type(opts.llm) ~= "table" then
    opts.llm = {}
  end

  if opts.llm.models then
    error(
      "llm.models is no longer supported. Use llm.provider and llm.model directly instead. "
        .. "See :help inliner for the new configuration format."
    )
  end

  if type(opts.llm.timeout) == "number" and opts.llm.timeout <= 0 then
    error("llm.timeout must be a positive number")
  end

  M.config = vim.tbl_deep_extend("force", M.config, opts)

  if not M.config.llm.provider then
    M.config.llm.provider = "openai"
  end

  if not VALID_PROVIDER_MAP[M.config.llm.provider] then
    error(
      string.format(
        "llm.provider must be one of: %s (got: %s)",
        table.concat(VALID_PROVIDERS, ", "),
        M.config.llm.provider
      )
    )
  end

  logger.init(M.config)

  setup_highlight_groups()

  if M.config.keys then
    for _, key in ipairs(M.config.keys) do
      local mode = key.mode or "n"
      local key_opts = { desc = key.desc }
      vim.keymap.set(mode, key[1], key[2], key_opts)
    end
  end

  setup_called = true
end



function M.edit()
  if not setup_called then
    vim.notify(
      '[inliner] setup() never called — using defaults. Call require("inliner").setup({}) in your config.',
      vim.log.levels.WARN
    )
  end

  local start_time = vim.loop.hrtime()
  logger.info("edit", "Edit operation started")

  local sel = selection.get_visual_selection()
  if not sel then
    sel = selection.get_line_selection()
    logger.info("edit", "No visual selection, using current line " .. sel.start_line)
  end

  if not vim.api.nvim_buf_is_valid(sel.bufnr) then
    logger.warn("edit", "Buffer was closed before edit request started, aborting")
    return
  end

  local start_mark = vim.api.nvim_buf_set_extmark(sel.bufnr, SELECTION_NS, sel.start_line - 1, 0, {})
  local end_mark = vim.api.nvim_buf_set_extmark(sel.bufnr, SELECTION_NS, sel.end_line - 1, 0, {})

  local function cleanup_selection_extmarks()
    if not vim.api.nvim_buf_is_valid(sel.bufnr) then
      return
    end

    vim.api.nvim_buf_del_extmark(sel.bufnr, SELECTION_NS, start_mark)
    vim.api.nvim_buf_del_extmark(sel.bufnr, SELECTION_NS, end_mark)
  end

  input.get_instruction(M.config, function(instruction)
    if not vim.api.nvim_buf_is_valid(sel.bufnr) then
      logger.warn("edit", "Buffer was closed before edit request started, aborting")
      return
    end

    logger.debug("edit", "User instruction: " .. instruction)
    logger.debug("edit", "Selected code:", sel.text)
    logger.debug(
      "edit",
      string.format(
        "Selection details: lines %d-%d, cols %d-%d",
        sel.start_line,
        sel.end_line,
        sel.start_col,
        sel.end_col
      )
    )
    logger.debug("edit", "System prompt:", M.config.system_prompt)

    logger.debug(
      "edit",
      string.format("Using model: %s (provider: %s)", M.config.llm.model or "default", M.config.llm.provider)
    )

    spinner.start("Processing edit...")

    llm.request_edit({
      code = sel.text,
      instruction = instruction,
      systemPrompt = M.config.system_prompt,
      provider = M.config.llm.provider,
      model = M.config.llm.model,
      baseURL = M.config.llm.base_url,
      maxOutputTokens = M.config.llm.max_output_tokens,
      timeout = M.config.llm.timeout,
    }, function(result, error)
      vim.schedule(function()
        spinner.stop()

        if not vim.api.nvim_buf_is_valid(sel.bufnr) then
          logger.warn("edit", "Buffer was closed during edit, aborting")
          return
        end

        local sm = vim.api.nvim_buf_get_extmark_by_id(sel.bufnr, SELECTION_NS, start_mark, {})
        local em = vim.api.nvim_buf_get_extmark_by_id(sel.bufnr, SELECTION_NS, end_mark, {})
        cleanup_selection_extmarks()

        if error then
          local elapsed = (vim.loop.hrtime() - start_time) / 1e9
          logger.error("edit", string.format("Edit failed after %.2fs: %s", elapsed, error))
          vim.notify("[inliner] " .. error, vim.log.levels.ERROR)
          return
        end

        if #sm == 0 or #em == 0 then
          local elapsed = (vim.loop.hrtime() - start_time) / 1e9
          logger.warn(
            "edit",
            string.format(
              "Selection extmarks were lost after %.2fs; aborting edit to avoid applying at a stale position",
              elapsed
            )
          )
          vim.notify(
            "[inliner] Edit aborted: selection changed and could not be reliably relocated",
            vim.log.levels.WARN
          )
          return
        end

        sel.start_line = sm[1] + 1
        sel.end_line = em[1] + 1

        logger.debug("edit", "Final result:", result)

        if M.config.diff_mode then
          diff.inject_conflict_markers(sel, result)
          local elapsed = (vim.loop.hrtime() - start_time) / 1e9
          logger.info("edit", string.format("Diff injected in %.2fs - awaiting resolution", elapsed))
        else
          replace.replace_selection(sel, result)
          local elapsed = (vim.loop.hrtime() - start_time) / 1e9
          logger.info("edit", string.format("Edit completed successfully in %.2fs", elapsed))
          vim.notify("[inliner] Edit applied", vim.log.levels.INFO)
        end
      end)
    end)
  end, cleanup_selection_extmarks)
end

function M.explain()
  if not setup_called then
    vim.notify(
      '[inliner] setup() never called — using defaults. Call require("inliner").setup({}) in your config.',
      vim.log.levels.WARN
    )
  end

  require("inliner.explain").explain()
end

function M.question()
  if not setup_called then
    vim.notify(
      '[inliner] setup() never called — using defaults. Call require("inliner").setup({}) in your config.',
      vim.log.levels.WARN
    )
  end

  require("inliner.question").open(M.config.question)
end

M.diff = diff

return M
