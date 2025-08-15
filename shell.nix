{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs_24
    nodePackages.npm
    nodePackages.yarn
  ];
  
  shellHook = ''
    echo "Node.js development environment"
    echo "Node version: $(node --version)"
    echo "npm version: $(npm --version)"
  '';
}