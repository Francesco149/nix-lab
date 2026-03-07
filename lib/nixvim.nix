{ pkgs, ... }:
{
  opts = {
    tabstop = 2;
    shiftwidth = 2;
    expandtab = true;
    clipboard = "unnamedplus";
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>e";
      action = "<cmd>lua vim.diagnostic.open_float()<cr>";
    }
  ];

  plugins = {

    lsp = {
      enable = true;
      servers.nil_ls.enable = true;
    };

    blink-cmp.enable = true;

    conform-nvim = {
      enable = true;
      settings.formatters_by_ft.nix = [ "nixfmt" ];
      settings.format_on_save = {
        timeout_ms = 500;
        lsp_fallback = true;
      };
    };

    render-markdown-nvim = {
      enable = true;
      settings = {
        heading.sign = false; # cleaner without signs in the gutter
        code.sign = false;
      };
    };

  };

  extraPlugins = [ pkgs.vimPlugins.vim-table-mode ];
  extraConfigLua = ''
    vim.g.table_mode_corner = '|'
  '';
}
