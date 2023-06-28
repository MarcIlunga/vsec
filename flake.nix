{
  description = "VsEc, A language server for EasyCrypt";

  inputs = {

    flake-utils.url = "github:numtide/flake-utils";

  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
  
   rec {

    packages.default =
      # Notice the reference to nixpkgs here.
      with import nixpkgs { inherit system; };
      
      ocamlPackages.buildDunePackage {
        duneVersion = "3";
        pname = "ec-language-server";
        version = "1.0.0-beta1";
        src = ./src;
        buildInputs = [
          dune_3
        ] ++ (with ocamlPackages; [
          camlp-streams
          ocaml
          yojson
          findlib
          ppx_inline_test
          ppx_assert
          ppx_sexp_conv
          ppx_deriving
          sexplib
          ppx_yojson_conv
          uri
        ]) ++ (easycrypt.buildInputs) 
        ++ (easycrypt.propagatedBuildInputs) 
        ++ (easycrypt.nativeBuildInputs);
      };

    devShells.default =
      with import nixpkgs { inherit system; };
      mkShell {
        buildInputs =
          self.packages.${system}.default.buildInputs
          ++ (with ocamlPackages; [
            ocaml-lsp
          ]);
      };

  });
}
