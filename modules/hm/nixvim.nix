# nixvim expects a bare attrset for the package generator.
# we make a wrapper module for the bare attrset.
# it can also be built as a package from the same attrset as needed.

{
  inputs,
  imports ? [ ],
}:
{
  imports = [ inputs.nixvim.homeModules.nixvim ];
  programs.nixvim = {
    enable = true;
    imports = [ ../../lib/nixvim.nix ] ++ imports;
  };
}
