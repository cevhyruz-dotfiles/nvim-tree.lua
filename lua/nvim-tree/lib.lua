local renderer = require "nvim-tree.renderer"
local view = require "nvim-tree.view"
local core = require "nvim-tree.core"
local utils = require "nvim-tree.utils"
local events = require "nvim-tree.events"

---@class LibOpenOpts
---@field path string|nil path
---@field current_window boolean|nil default false

local M = {
  target_winid = nil,
}

function M.get_node_at_cursor()
  if not core.get_explorer() then
    return
  end

  local winnr = view.get_winnr()
  if not winnr then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(view.get_winnr())
  local line = cursor[1]

  if line == 1 and view.is_root_folder_visible(core.get_cwd()) then
    return { name = ".." }
  end

  return utils.get_nodes_by_line(core.get_explorer().nodes, core.get_nodes_starting_line())[line]
end

---Create a sanitized partial copy of a node, populating children recursively.
---@param node table
---@return table|nil cloned node
local function clone_node(node)
  if not node then
    node = core.get_explorer()
    if not node then
      return nil
    end
  end

  local n = {
    absolute_path = node.absolute_path,
    executable = node.executable,
    extension = node.extension,
    git_status = node.git_status,
    has_children = node.has_children,
    hidden = node.hidden,
    link_to = node.link_to,
    name = node.name,
    open = node.open,
    type = node.type,
  }

  if type(node.nodes) == "table" then
    n.nodes = {}
    for _, child in ipairs(node.nodes) do
      table.insert(n.nodes, clone_node(child))
    end
  end

  return n
end

---Api.tree.get_nodes
function M.get_nodes()
  return clone_node(core.get_explorer())
end

-- If node is grouped, return the last node in the group. Otherwise, return the given node.
function M.get_last_group_node(node)
  local next = node
  while next.group_next do
    next = next.group_next
  end
  return next
end

function M.expand_or_collapse(node)
  node.open = not node.open
  if node.has_children then
    node.has_children = false
  end

  if #node.nodes == 0 then
    core.get_explorer():expand(node)
  end

  renderer.draw()
end

function M.set_target_win()
  local id = vim.api.nvim_get_current_win()
  local tree_id = view.get_winnr()
  if tree_id and id == tree_id then
    M.target_winid = 0
    return
  end

  M.target_winid = id
end

local function handle_buf_cwd(cwd)
  if M.respect_buf_cwd and cwd ~= core.get_cwd() then
    require("nvim-tree.actions.root.change-dir").fn(cwd)
  end
end

local function open_view_and_draw()
  local cwd = vim.fn.getcwd()
  view.open()
  handle_buf_cwd(cwd)
  renderer.draw()
end

local function should_hijack_current_buf()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local bufmodified = vim.api.nvim_buf_get_option(bufnr, "modified")
  local ft = vim.api.nvim_buf_get_option(bufnr, "ft")

  local should_hijack_unnamed = M.hijack_unnamed_buffer_when_opening and bufname == "" and not bufmodified and ft == ""
  local should_hijack_dir = bufname ~= "" and vim.fn.isdirectory(bufname) == 1 and M.hijack_directories.enable

  return should_hijack_dir or should_hijack_unnamed
end

function M.prompt(prompt_input, prompt_select, items_short, items_long, callback)
  local function format_item(short)
    for i, s in ipairs(items_short) do
      if short == s then
        return items_long[i]
      end
    end
    return ""
  end

  if M.select_prompts then
    vim.ui.select(items_short, { prompt = prompt_select, format_item = format_item }, function(item_short)
      callback(item_short)
    end)
  else
    vim.ui.input({ prompt = prompt_input }, function(item_short)
      callback(item_short)
    end)
  end
end

---Open the tree, initialising as needed. Maybe hijack the current buffer.
---@param opts LibOpenOpts|nil
function M.open(opts)
  opts = opts or {}

  M.set_target_win()
  if not core.get_explorer() or opts.path then
    core.init(opts.path or vim.loop.cwd())
  end
  if should_hijack_current_buf() then
    view.close_this_tab_only()
    view.open_in_current_win()
    renderer.draw()
  elseif opts.current_window then
    view.open_in_current_win { hijack_current_buf = false, resize = false }
    renderer.draw()
  else
    open_view_and_draw()
  end
  view.restore_tab_state()
  events._dispatch_on_tree_open()
end

function M.setup(opts)
  M.hijack_unnamed_buffer_when_opening = opts.hijack_unnamed_buffer_when_opening
  M.hijack_directories = opts.hijack_directories
  M.respect_buf_cwd = opts.respect_buf_cwd
  M.select_prompts = opts.select_prompts
end

return M
