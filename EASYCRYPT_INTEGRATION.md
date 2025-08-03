# EasyCrypt Integration Guide

## Overview

This document describes the EasyCrypt submodule integration in VsEc. The EasyCrypt submodule has been initialized and provides access to the full EasyCrypt library implementation.

## Submodule Status

- **Location**: `src/easycrypt/`
- **Commit**: `757ec0952b90caa86ca490397ec6bb460e95dbd2`
- **Branch**: `main`
- **Repository**: `git@github.com:EasyCrypt/easycrypt.git`

## Available Modules

The EasyCrypt library is exposed as `easycrypt.ecLib` in dune. Key modules include:

### Core Language
- `EcParser` - Parser for EasyCrypt syntax
- `EcLexer` - Lexical analyzer
- `EcParsetree` - Abstract syntax tree definitions
- `EcLocation` - Source location tracking

### Type System
- `EcTypes` - Type definitions
- `EcTyping` - Type checking
- `EcUnify` - Type unification

### State Management
- `EcScope` - Proof contexts and scoping
- `EcGState` - Global state
- `EcEnv` - Environment management

### Logic and Proofs
- `EcFol` - First-order logic
- `EcCoreFol` - Core formula operations
- `EcCoreGoal` - Goal management
- `EcProofTerm` - Proof terms

### Additional Components
- `EcModules` - Module system
- `EcTheory` - Theory management
- `EcCommands` - Command processing
- `EcUserMessages` - User-facing messages

## Integration Points

### 1. Parser Integration
The parser integration (Roadmap item 1.2) will use:
```ocaml
(* In src/dm/document.ml *)
let parse_more parsing_state stream raw_doc =
  let lexbuf = Lexing.from_string (Stream.contents stream) in
  try
    let ast = EcLib.EcParser.global_sentence EcLib.EcLexer.main lexbuf in
    (* Convert to internal representation *)
    ...
  with
  | EcLib.EcParser.Error ->
    (* Handle parse errors *)
    ...
```

### 2. State Management
Execution will use:
```ocaml
(* In src/dm/executionManager.ml *)
let execute_sentence scope sentence =
  let new_scope = EcLib.EcScope.exec scope sentence in
  (* Handle execution results *)
  ...
```

### 3. Error Reporting
Diagnostics will use:
```ocaml
(* Convert EasyCrypt locations to LSP ranges *)
let ec_loc_to_range (loc: EcLib.EcLocation.t) =
  let start = loc.loc_start in
  let end_ = loc.loc_end in
  (* Convert to LSP Range *)
  ...
```

## Dependencies

The EasyCrypt library requires additional OPAM packages:
- `batteries` (>= 3)
- `camlp-streams` (>= 5)
- `camlzip`
- `ocaml-inifiles` (>= 1.2)
- `pcre` (>= 7)
- `why3` (>= 1.6.0, < 1.7)
- `yojson`
- `zarith` (>= 1.10)

These are specified in `src/easycrypt/easycrypt.opam`.

## Build Configuration

The integration is configured in dune files:

```dune
(library
 (name dm)
 (libraries base sel lsp easycrypt.ecLib))
```

## Next Steps

With the submodule initialized, the next roadmap items are:
1. **Parser Integration (1.2)** - Implement `parse_more` function
2. **Execution Engine (2.1)** - Replace Coq execution with EasyCrypt
3. **Error Diagnostics (2.2)** - Convert EasyCrypt errors to LSP diagnostics

## Testing

Integration tests are provided in `src/tests/test_easycrypt_integration.ml` to verify:
- Module accessibility
- Basic type creation
- Location handling
- Parser token access

Note: Full integration testing requires EasyCrypt dependencies to be installed.