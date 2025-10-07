# CLAUDE.md

This file provides guidance to AI assistants (Claude, GPT, etc.) when working with code in this repository.

## 🚨 **CRITICAL: GIT SAFETY RULES** 🚨

### **ABSOLUTE PROHIBITIONS - NO EXCEPTIONS**

**NEVER, UNDER ANY CIRCUMSTANCES:**
- ❌ Run `git reset --hard` without EXPLICIT user permission
- ❌ Run `git reset --soft` without EXPLICIT user permission  
- ❌ Run `git clean -fd` without EXPLICIT user permission
- ❌ Run `git push --force` without EXPLICIT user permission
- ❌ Delete branches without EXPLICIT user permission
- ❌ Modify `.git/` directory contents
- ❌ Run any destructive git command that loses history

**IF YOU ACCIDENTALLY LOSE WORK:**
- Work can be recovered from `.specstory/history/` files
- Check for VSIX packages in `vscode-extension/` (contain compiled code)
- Use `git reflog` to find lost commits
- Extract source from binaries using `objdump`, `strings`, `nm -C`

**BEFORE ANY GIT OPERATION:**
1. Always use `git status` first
2. Ask user for confirmation on destructive operations
3. Create a backup branch if unsure: `git branch backup-$(date +%s)`

---

## Project Overview

VsEc is a Language Server Protocol (LSP) implementation for EasyCrypt, adapted from VSCoq. It provides VS Code IDE support for the EasyCrypt proof assistant with interactive proving capabilities.

**Tech Stack:**
- **Backend**: OCaml 4.14+ with Dune build system
- **Frontend**: TypeScript/React with Vite
- **LSP**: Based on OCaml LSP library
- **EasyCrypt**: Integrated via opam packages

---

## Build Commands

### **Primary Build Script** (Use this for everything!)

```bash
# Build server only
./build-extension.sh -l
# OR
./build_lsp.sh build server

# Build extension (TypeScript + webview)
./build_lsp.sh build extension

# Full build (server + extension + webview)
./build_lsp.sh build

# Create VSIX package (full build + packaging)
./build_lsp.sh package
```

### Manual Commands (if build script fails)

```bash
# OCaml LSP Server
cd src && dune build

# TypeScript Extension
cd vscode-extension && npm install && npm run compile

# React Webview UI
cd vscode-extension/goal-view-ui && npm install && npm run build
```

### Testing

```bash
# OCaml unit tests
cd src && dune runtest

# Run specific test
dune exec src/tests/test_interactive_suite.exe

# TypeScript tests
cd vscode-extension && npm test
```

---

## Architecture

### Directory Structure

```
src/                          # OCaml LSP Server
├── eclsp/                    # LSP server entry point
│   └── lspManager.ml         # Main LSP request/notification handlers
├── dm/                       # Document Manager
│   ├── documentManager.ml    # Document state & execution management
│   ├── types.ml              # Type definitions (SentenceId, etc.)
│   └── plugins/              # EasyCrypt adapter plugins
├── protocol/                 # Protocol types
│   ├── proofState.ml         # ProofState with error_message field
│   ├── ast.ml                # AST serialization (EasyCrypt → JSON)
│   └── messages.ml           # Structured message types
└── tests/                    # Comprehensive test suite (18 files)

vscode-extension/             # VS Code Extension
├── src/                      # TypeScript extension host
│   ├── extension.ts          # Main entry point
│   ├── panels/GoalPanel.ts   # Webview panel management
│   ├── webviewTypes.ts       # Type definitions for webview messages
│   └── test/                 # TypeScript tests
└── goal-view-ui/             # React webview UI
    └── src/
        ├── components/       # React components
        └── types.ts          # ProofState, Goal types

scripts/                      # Utility scripts
├── extract_easycrypt_types.py  # Type extraction from EasyCrypt
├── agent_manager.py          # Agent task dispatcher
└── watch_agents.py           # Agent monitoring tool
```

### Key Files

**Critical OCaml Files:**
- `src/dm/documentManager.ml` - Document state, observe_id tracking, cancel_handle management
- `src/eclsp/lspManager.ml` - LSP handlers, notifications, command dispatch
- `src/protocol/proofState.ml` - ProofState type with error handling
- `src/protocol/ast.ml` - EasyCrypt AST → JSON serialization (318 lines)
- `src/dm/types.ml` - SentenceId module, DiagnosticSeverity, RangeList

**Critical TypeScript Files:**
- `vscode-extension/src/extension.ts` - Extension activation, LSP client
- `vscode-extension/src/panels/GoalPanel.ts` - Webview lifecycle, message passing
- `vscode-extension/goal-view-ui/src/types.ts` - ProofState interface (includes in_proof, error_message)
- `vscode-extension/src/webviewTypes.ts` - Discriminated unions for type safety

---

## Recent Critical Fixes (October 2025)

### Memory Leaks Fixed
1. **cancel_handle cleanup** (documentManager.ml:602)
   - Added `let state = { state with cancel_handle = None }` after cancellation
   - Prevents dangling event handle references

2. **Document cleanup on close** (lspManager.ml:1240-1245)
   - Properly removes document state from hashtable
   - Cancels execution and destroys ExecutionManager state

### Critical Bug Fixes
1. **observe_id tracking** (documentManager.ml:313, 319)
   - Forward execution now updates `observe_id = Id id`
   - "Next" command advances correctly
   - Interpret-to-cursor establishes correct baseline

### Type Safety Improvements
1. **error_message field** - Added to ProofState.t throughout stack
2. **TypeScript strict mode** - Enabled in all tsconfig.json files
3. **Discriminated unions** - For webview message types
4. **AST serialization** - Complete EasyCrypt type → JSON infrastructure

---

## Development Workflow

### Making Changes

1. **Always check git status first:**
   ```bash
   git status
   ```

2. **Create a branch for new features:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Build and test after changes:**
   ```bash
   ./build_lsp.sh build && dune runtest
   ```

4. **Commit with descriptive messages:**
   ```bash
   git add <files>
   git commit -m "feat: description of changes"
   ```

### Code Style

**OCaml:**
- Use `let () =` for side effects
- Prefer `Result.t` over exceptions for error handling
- Use smart constructors for types with invariants
- Document all public functions in .mli files

**TypeScript:**
- Enable `strict: true`, `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`
- Use discriminated unions for message types
- Avoid `any` - use proper types or `unknown`
- Guard array/string accesses for `undefined`

---

## Common Tasks

### Adding a New LSP Command

1. Add handler in `src/eclsp/lspManager.ml`
2. Register command in `vscode-extension/src/extension.ts`
3. Update command palette entries in `package.json`
4. Test with both TypeScript and OCaml tests

### Modifying ProofState

1. Update `src/protocol/proofState.ml` and `.mli`
2. Update `vscode-extension/goal-view-ui/src/types.ts`
3. Verify serialization with `@@deriving yojson`
4. Test full round-trip (OCaml → JSON → TypeScript)

### Debugging LSP

```bash
# Enable LSP logging
export VSEC_LSP_LOG=debug

# Watch LSP output in VS Code
# View → Output → Select "VsEc Language Server"

# Manual LSP testing
./test_lsp_manual.sh
```

---

## Testing

### Test Coverage

**OCaml Tests (18 files):**
- `test_ast_serialization.ml` - AST → JSON conversion
- `test_interactive_suite.ml` - End-to-end interactive proving
- `test_lsp_integration.ml` - LSP protocol compliance
- `test_query_commands.ml` - Query command functionality
- `test_step_forward.ml` - Proof stepping
- And 13 more comprehensive tests

**TypeScript Tests:**
- `queryCommands.test.ts` - Query command edge cases

### Running Tests

```bash
# All OCaml tests
cd src && dune runtest

# Specific test suite
dune exec src/tests/test_interactive_suite.exe

# With coverage
dune runtest --instrument-with bisect_ppx

# TypeScript tests  
cd vscode-extension && npm test
```

---

## Packaging

```bash
# Create VSIX package
./build_lsp.sh package

# Output: vscode-extension/vsec-easycrypt-X.Y.Z.vsix
# Size: ~29 MB (includes 45 MB OCaml binary)

# Install locally
code --install-extension vscode-extension/vsec-easycrypt-*.vsix
```

---

## Troubleshooting

### Build Fails

```bash
# Clean everything
dune clean
rm -rf vscode-extension/node_modules vscode-extension/goal-view-ui/node_modules

# Rebuild from scratch
./build_lsp.sh build
```

### LSP Not Starting

1. Check `which easycrypt` - EasyCrypt must be installed
2. Check VS Code Output panel for errors
3. Verify `vscode-extension/vsec-lsp` binary exists
4. Try manual build: `cd src && dune build`

### Type Errors After Changes

1. Rebuild OCaml: `cd src && dune build`
2. Rebuild TypeScript: `cd vscode-extension && npm run compile`
3. Check type definitions match: compare `proofState.ml` vs `types.ts`

---

## Important Notes

### DO NOT:
- ❌ Commit build artifacts (`.js`, `.d.ts`, `_build/`, `node_modules/`)
- ❌ Commit VSIX files
- ❌ Commit `.specstory/` history files
- ❌ Run git operations without checking status first
- ❌ Use `git reset --hard` (see warnings at top!)

### DO:
- ✅ Use `./build_lsp.sh` for all builds
- ✅ Run tests after changes
- ✅ Update both .ml and .mli when changing interfaces
- ✅ Keep TypeScript types in sync with OCaml types
- ✅ Write tests for new features
- ✅ Ask user before destructive operations

---

## Resources

- **EasyCrypt**: https://github.com/EasyCrypt/easycrypt
- **LSP Spec**: https://microsoft.github.io/language-server-protocol/
- **VSCoq** (original): https://github.com/coq-community/vscoq
- **Dune Docs**: https://dune.readthedocs.io/

---

## Recovery Information (In Case of Emergency)

If work is lost due to git issues:

1. **Check reflog**: `git reflog --all` to find lost commits
2. **Check VSIX files**: They contain compiled source code
3. **Check specstory**: `.specstory/history/*.md` files contain detailed session logs
4. **Binary analysis**: Use `objdump`, `strings`, `nm -C` on `vsec-lsp` binary
5. **JavaScript recovery**: Use `js-beautify` on compiled `.js` files in VSIX

**Last Resort**: The working VSIX is at `vscode-extension/vsec-easycrypt-0.1.19.vsix`

---

*Last Updated: October 7, 2025*
*Version: Post-Recovery (7 commits restoring 6,400+ lines)*
