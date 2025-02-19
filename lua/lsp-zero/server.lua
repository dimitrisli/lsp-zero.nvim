local M = {
  default_config = false,
  common_attach = nil,
  enable_keymaps = false,
}

local s = {}

local state = {
  exclude = {},
  capabilities = nil,
  omit_keys = {n = {}, i = {}, x = {}},
}

function M.extend_lspconfig()
  -- Set on_attach hook
  local lsp_cmds = vim.api.nvim_create_augroup('lsp_zero_attach', {clear = true})
  vim.api.nvim_create_autocmd('LspAttach', {
    group = lsp_cmds,
    desc = 'lsp-zero on_attach',
    callback = function(event)
      local bufnr = event.buf

      if type(M.enable_keymaps) == 'table' then
        M.default_keymaps({
          buffer = bufnr,
          preserve_mappings = M.enable_keymaps.preserve_mappings,
          omit = M.enable_keymaps.omit,
        })
      end

      s.set_buf_commands(bufnr)

      if M.common_attach then
        local client = vim.lsp.get_client_by_id(event.data.client_id)
        M.common_attach(client, bufnr)
      end
    end
  })

  local ok, lspconfig = pcall(require, 'lspconfig')
  if not ok then
    return
  end

  local util = lspconfig.util

  -- Set client capabilities
  util.default_config.capabilities = s.set_capabilities()

  -- Ensure proper setup
  util.on_setup = util.add_hook_after(util.on_setup, function(config, user_config)
    M.setup_installer()
    M.skip_server(config.name)
    if type(M.default_config) == 'table' then
      s.apply_global_config(config, user_config, M.default_config)
    end
  end)
end

function M.setup(name, opts)
  if state.exclude[name] then
    return
  end

  local lsp = require('lspconfig')[name]
  lsp.setup(opts or {})
end

function M.set_default_capabilities(opts)
  local defaults = require('lspconfig').util.default_config
  defaults.capabilities = s.set_capabilities(opts)
end

function M.set_global_commands()
  local command = vim.api.nvim_create_user_command

  command('LspZeroWorkspaceAdd', 'lua vim.lsp.buf.add_workspace_folder()', {})

  command(
    'LspZeroWorkspaceList',
    'lua vim.notify(vim.inspect(vim.lsp.buf.list_workspace_folders()))',
    {}
  )
end

function M.diagnostics_config()
  return {severity_sort = true}
end

function M.default_keymaps(opts)
  local fmt = function(cmd) return function(str) return cmd:format(str) end end

  local buffer = opts.buffer or 0
  local keep_defaults = true
  local omit = {}

  if type(opts.preserve_mappings) == 'boolean' then
    keep_defaults = opts.preserve_mappings
  end

  if type(opts.omit) == 'table' then
    omit = opts.omit
  end

  local lsp = fmt('<cmd>lua vim.lsp.%s<cr>')
  local diagnostic = fmt('<cmd>lua vim.diagnostic.%s<cr>')

  local map = function(m, lhs, rhs)
    if vim.tbl_contains(omit, lhs) then
      return
    end

    if keep_defaults and s.map_check(m, lhs) then
      return
    end

    local key_opts = {buffer = buffer}
    vim.keymap.set(m, lhs, rhs, key_opts)
  end

  map('n', 'K', lsp 'buf.hover()')
  map('n', 'gd', lsp 'buf.definition()')
  map('n', 'gD', lsp 'buf.declaration()')
  map('n', 'gi', lsp 'buf.implementation()')
  map('n', 'go', lsp 'buf.type_definition()')
  map('n', 'gr', lsp 'buf.references()')
  map('n', 'gs', lsp 'buf.signature_help()')
  map('n', '<F2>', lsp 'buf.rename()')
  map('n', '<F3>', lsp 'buf.format({async = true})')
  map('x', '<F3>', lsp 'buf.format({async = true})')
  map('n', '<F4>', lsp 'buf.code_action()')

  if vim.lsp.buf.range_code_action then
    map('x', '<F4>', lsp 'buf.range_code_action()')
  else
    map('x', '<F4>', lsp 'buf.code_action()')
  end

  map('n', 'gl', diagnostic 'open_float()')
  map('n', '[d', diagnostic 'goto_prev()')
  map('n', ']d', diagnostic 'goto_next()')
end

function M.set_sign_icons(opts)
  opts = opts or {}

  local sign = function(args)
    if opts[args.name] == nil then
      return
    end

    vim.fn.sign_define(args.hl, {
      texthl = args.hl,
      text = opts[args.name],
      numhl = ''
    })
  end

  sign({name = 'error', hl = 'DiagnosticSignError'})
  sign({name = 'warn', hl = 'DiagnosticSignWarn'})
  sign({name = 'hint', hl = 'DiagnosticSignHint'})
  sign({name = 'info', hl = 'DiagnosticSignInfo'})
end

function M.nvim_workspace(opts)
  local runtime_path = vim.split(package.path, ';')
  table.insert(runtime_path, 'lua/?.lua')
  table.insert(runtime_path, 'lua/?/init.lua')

  local config = {
    settings = {
      Lua = {
        -- Disable telemetry
        telemetry = {enable = false},
        runtime = {
          -- Tell the language server which version of Lua you're using
          -- (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          path = runtime_path,
        },
        diagnostics = {
          -- Get the language server to recognize the `vim` global
          globals = {'vim'}
        },
        workspace = {
          checkThirdParty = false,
          library = {
            -- Make the server aware of Neovim runtime files
            vim.fn.expand('$VIMRUNTIME/lua'),
            vim.fn.stdpath('config') .. '/lua'
          }
        }
      }
    }
  }

  return vim.tbl_deep_extend('force', config, opts or {})
end

function M.client_capabilities()
  if state.capabilities == nil then
    return s.set_capabilities()
  end

  return state.capabilities
end

function s.set_buf_commands(bufnr)
  local bufcmd = vim.api.nvim_buf_create_user_command
  local format = function(input)
    if #input.fargs > 2 then
      vim.notify('Too many arguments for LspZeroFormat', vim.log.levels.ERROR)
      return
    end

    local server = input.fargs[1]
    local timeout = input.fargs[2]

    if timeout and timeout:find('timeout=') then
      timeout = timeout:gsub('timeout=', '')
      timeout = tonumber(timeout)
    end

    if server and server:find('timeout=') then
      timeout = server:gsub('timeout=', '')
      timeout = tonumber(timeout)
      server = input.fargs[2]
    end

    vim.lsp.buf.format({
      async = input.bang,
      timeout_ms = timeout,
      name = server,
    })
  end

  bufcmd(bufnr, 'LspZeroFormat', format, {range = true, bang = true, nargs = '*'})

  bufcmd(
    bufnr,
    'LspZeroWorkspaceRemove',
    'lua vim.lsp.buf.remove_workspace_folder()',
    {}
  )
end

function M.skip_server(name)
  if type(name) == 'string' then
    state.exclude[name] = true
  end
end

function M.setup_installer()
  local installer = require('lsp-zero.installer')
  local config = require('lsp-zero.settings').get()

  if config.call_servers == 'local' and installer.state == 'init' then
    installer.setup()
  end

  M.setup_installer = function() end
end

function s.set_capabilities(current)
  if state.capabilities == nil then
    local cmp_txt = vim.api.nvim_get_runtime_file('doc/cmp.txt', 1)
    local ok_lsp_source, cmp_lsp = pcall(require, 'cmp_nvim_lsp')
    local cmp_default_capabilities = {}
    local base = {}

    local ok_lspconfig, lspconfig = pcall(require, 'lspconfig')

    if ok_lspconfig then
      base = lspconfig.util.default_config.capabilities
    else
      base = vim.lsp.protocol.make_client_capabilities()
    end

    if #cmp_txt > 0 and ok_lsp_source then
       cmp_default_capabilities = cmp_lsp.default_capabilities()
    end

    state.capabilities = vim.tbl_deep_extend(
      'force',
      base,
      cmp_default_capabilities,
      current or {}
    )

    return state.capabilities
  end

  if current == nil then
    return state.capabilities
  end

  return vim.tbl_deep_extend('force', state.capabilities, current)
end

function s.map_check(mode, lhs)
  local cache = state.omit_keys[mode][lhs]
  if cache == nil then
    local available = vim.fn.mapcheck(lhs, mode) == ''
    state.omit_keys[mode][lhs] = not available

    return not available
  end

  return cache
end

function s.apply_global_config(config, user_config, defaults)
  local new_config = vim.deepcopy(defaults)
  s.tbl_merge(new_config, user_config)

  for key, val in pairs(new_config) do
    if type(val) == 'table' and not vim.tbl_islist(val) then
      s.tbl_merge(config[key], val)
    elseif (
      key == 'on_new_config'
      and config[key]
      and config[key] ~= new_config[key]
    ) then
      config[key] = s.compose_fn(config[key], new_config[key])
    else
      config[key] = val
    end
  end
end

function s.compose_fn(config_callback, user_callback)
  return function(...)
    config_callback(...)
    user_callback(...)
  end
end

function s.tbl_merge(old_val, new_val)
  for k, v in pairs(new_val) do
    if type(v) == 'table' and not vim.tbl_islist(v) then
      s.tbl_merge(old_val[k], v)
    else
      old_val[k] = v
    end
  end
end

return M

