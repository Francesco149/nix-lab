{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) lab;
  colors = lab.colors;

  treeSitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    p: with p; [
      bash
      c
      c_sharp
      cpp
      fish
      gdscript
      javascript
      json
      lua
      nix
      python
      svelte
      typescript
      zig
    ]
  );

  runtimePackages = with pkgs; [
    bash-language-server
    clang-tools
    csharp-ls
    csharpier
    fd
    fish
    fish-lsp
    lua-language-server
    nil
    nixfmt
    prettierd
    pyright
    ripgrep
    ruff
    shellcheck
    shfmt
    stylua
    svelte-language-server
    typescript
    typescript-language-server
    zls
  ];

  luaConfig = ''
    vim.g.mapleader = ' '
    vim.g.maplocalleader = ' '

    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.expandtab = true
    vim.opt.shiftwidth = 2
    vim.opt.softtabstop = 2
    vim.opt.tabstop = 2
    vim.opt.smartindent = true
    vim.opt.termguicolors = true
    vim.opt.signcolumn = 'yes'
    vim.opt.updatetime = 300
    vim.opt.timeoutlen = 400
    vim.opt.completeopt = { 'menu', 'menuone', 'noinsert', 'noselect' }
    vim.opt.clipboard = 'unnamedplus'

    local function hi(group, opts)
      vim.api.nvim_set_hl(0, group, opts)
    end

    hi('Normal', { bg = 'NONE', fg = '#${colors.base05}' })
    hi('NormalNC', { bg = 'NONE' })
    hi('NormalFloat', { bg = 'NONE' })
    hi('FloatBorder', { bg = 'NONE', fg = '#${colors.base02}' })
    hi('EndOfBuffer', { bg = 'NONE', fg = '#${colors.base01}' })
    hi('LineNr', { fg = '#${colors.base01}' })
    hi('CursorLineNr', { fg = '#${colors.base0A}', bold = true })
    hi('Visual', { bg = '#${colors.base01}' })
    hi('Search', { bg = '#${colors.base0A}', fg = '#${colors.base00}' })
    hi('IncSearch', { bg = '#${colors.base09}', fg = '#${colors.base00}' })
    hi('DiagnosticError', { fg = '#${colors.base08}' })
    hi('DiagnosticWarn', { fg = '#${colors.base0A}' })
    hi('DiagnosticInfo', { fg = '#${colors.base0C}' })
    hi('DiagnosticHint', { fg = '#${colors.base02}' })

    for _, plugin in ipairs({
      'blink.cmp',
      'conform.nvim',
      'nvim-lspconfig',
      'nvim-treesitter',
      'plenary.nvim',
      'telescope.nvim',
    }) do
      vim.cmd.packadd(plugin)
    end

    if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
      local osc52 = require('vim.ui.clipboard.osc52')
      vim.g.clipboard = {
        name = 'OSC 52',
        copy = {
          ['+'] = osc52.copy('+'),
          ['*'] = osc52.copy('*'),
        },
        paste = {
          ['+'] = function() return { {}, 'v' } end,
          ['*'] = function() return { {}, 'v' } end,
        },
      }
    end

    vim.api.nvim_create_autocmd('FileType', {
      pattern = {
        'bash',
        'c',
        'cpp',
        'cs',
        'fish',
        'gdscript',
        'javascript',
        'json',
        'lua',
        'nix',
        'python',
        'sh',
        'svelte',
        'typescript',
        'zig',
      },
      callback = function()
        pcall(vim.treesitter.start)
      end,
    })

    require('telescope').setup({
      defaults = {
        prompt_prefix = '  ',
        selection_caret = '> ',
        file_ignore_patterns = { '/%.git/', '/%.direnv/', '/result[^/]*' },
        layout_config = {
          horizontal = { preview_width = 0.55 },
        },
      },
    })

    vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files, { desc = 'Find files' })
    vim.keymap.set('n', '<leader>fg', require('telescope.builtin').live_grep, { desc = 'Live grep' })
    vim.keymap.set('n', '<leader>fb', require('telescope.builtin').buffers, { desc = 'Buffers' })
    vim.keymap.set('n', '<leader>fh', require('telescope.builtin').help_tags, { desc = 'Help' })

    vim.diagnostic.config({
      virtual_text = false,
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = { border = 'rounded', source = 'if_many' },
    })

    local blink = require('blink.cmp')
    blink.setup({
      keymap = {
        preset = 'none',
        ['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },
        ['<C-e>'] = { 'hide' },
        ['<Tab>'] = { 'select_and_accept', 'fallback' },
        ['<S-Tab>'] = { 'select_prev', 'fallback' },
        ['<Up>'] = { 'select_prev', 'fallback' },
        ['<Down>'] = { 'select_next', 'fallback' },
      },
      completion = {
        menu = { auto_show = false },
        documentation = { auto_show = false },
        ghost_text = { enabled = false },
        list = {
          selection = {
            preselect = false,
            auto_insert = false,
          },
        },
      },
      signature = { enabled = false },
    })

    local capabilities = require('blink.cmp').get_lsp_capabilities()
    local servers = {
      bashls = {},
      clangd = {},
      csharp_ls = {},
      fish_lsp = {},
      gdscript = {},
      lua_ls = {
        settings = {
          Lua = {
            diagnostics = { globals = { 'vim' } },
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      },
      nil_ls = {},
      pyright = {},
      ruff = {},
      svelte = {},
      ts_ls = {},
      zls = {},
    }

    for name, opts in pairs(servers) do
      opts.capabilities = capabilities
      vim.lsp.config(name, opts)
      vim.lsp.enable(name)
    end

    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(args)
        local bufnr = args.buf
        local map = function(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
        end

        map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
        map('n', 'gr', vim.lsp.buf.references, 'References')
        map('n', 'K', vim.lsp.buf.hover, 'Hover')
        map('n', '<leader>rn', vim.lsp.buf.rename, 'Rename')
        map('n', '<leader>ca', vim.lsp.buf.code_action, 'Code action')

        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.server_capabilities.inlayHintProvider then
          vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
        end
      end,
    })

    local conform = require('conform')
    conform.setup({
      formatters_by_ft = {
        bash = { 'shfmt' },
        c = { 'clang_format' },
        cpp = { 'clang_format' },
        cs = { 'csharpier' },
        fish = { 'fish_indent' },
        javascript = { 'prettierd', 'prettier', stop_after_first = true },
        javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        json = { 'prettierd', 'prettier', stop_after_first = true },
        lua = { 'stylua' },
        nix = { 'nixfmt' },
        python = { 'ruff_format' },
        sh = { 'shfmt' },
        svelte = { 'prettierd', 'prettier', stop_after_first = true },
        typescript = { 'prettierd', 'prettier', stop_after_first = true },
        typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        zig = { 'zigfmt' },
      },
      format_on_save = function(bufnr)
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return
        end

        return {
          timeout_ms = 2000,
          lsp_format = 'fallback',
        }
      end,
    })

    vim.api.nvim_create_user_command('Format', function(args)
      conform.format({ async = false, lsp_format = 'fallback', timeout_ms = 4000 }, function(err)
        if err then
          vim.notify(err, vim.log.levels.ERROR)
        end
      end)
    end, {})

    vim.api.nvim_create_user_command('FormatDisable', function(args)
      if args.bang then
        vim.b.disable_autoformat = true
      else
        vim.g.disable_autoformat = true
      end
    end, { bang = true })

    vim.api.nvim_create_user_command('FormatEnable', function()
      vim.b.disable_autoformat = false
      vim.g.disable_autoformat = false
    end, {})
  '';

  labNeovim = pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
    luaRcContent = luaConfig;
    plugins = with pkgs.vimPlugins; [
      blink-cmp
      conform-nvim
      nvim-lspconfig
      plenary-nvim
      telescope-nvim
      treeSitter
    ];
    wrapperArgs = [
      "--suffix"
      "PATH"
      ":"
      (lib.makeBinPath runtimePackages)
    ];
  };

  e =
    pkgs.runCommand "e-${pkgs.neovim-unwrapped.version}" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        makeWrapper ${labNeovim}/bin/nvim $out/bin/e \
          --set NVIM_APPNAME labvim
      '';
in
{
  environment.systemPackages = [
    e
  ];
}
