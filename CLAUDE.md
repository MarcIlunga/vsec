# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VsEc is a Language Server Protocol (LSP) implementation for EasyCrypt, forked from VSCoq. It provides IDE support for the EasyCrypt proof assistant.

## Development Commands

### Build
```bash
# Build the project
dune build

# Build in watch mode (rebuilds on file changes)
dune build --watch
```

### Test
```bash
# Run all tests
dune runtest

# Run tests in watch mode
dune runtest --watch

# Run a specific test file
dune exec ./src/tests/<test_file>.exe
```

### Development Environment
```bash
# Enter Nix development shell (includes OCaml toolchain and LSP)
nix develop

# Or with direnv
direnv allow
```

### Release
```bash
# Create release package
cd src && ./make-release.sh
```

## Architecture

### Core Components

**SEL (Simple Event Library)** - Custom event loop (`src/sel/`)
- Alternative to threads/Lwt built on Unix.select
- Handles multiple event sources without blocking
- Key types: `'a Sel.event`, `Sel.wait`, `Sel.on_*` constructors

**Document Manager** (`src/dm/`)
- `scheduler`: Plans document execution, tracks dependencies
- `executionManager`: Manages EasyCrypt state and sentence execution
- `document`: Holds user text and validated/parsed form
- `documentManager`: Main API for document operations

**LSP Implementation** (`src/lsp/`)
- JSON-RPC protocol handling
- LSP message types and extended protocol support
- Integration with SEL event system

**Driver** (`src/driver/`)
- `ecLsp.ml`: Main executable entry point
- `lspManager.ml`: Handles LSP requests and VSCoq-specific messages

### Key Implementation Details

1. **Event Handling Pattern**: All async operations use SEL events
   ```ocaml
   type event = 
     | LspMessage of ... 
     | DocumentChange of ...
   let handle_event = function
     | LspMessage msg -> handle_lsp msg
     | DocumentChange doc -> update_document doc
   ```

2. **Document Processing**: Parsing and execution are entangled - validation stops at sentences with parsing effects

3. **State Management**: Global EasyCrypt state managed by executionManager

4. **Testing**: Uses `ppx_inline_test` for unit tests inline with implementation

## EasyCrypt Integration

The `src/easycrypt/` directory is reserved for EasyCrypt-specific components. Integration points:
- Build system references `easycrypt.ecLib`
- Document manager adapted for EasyCrypt syntax
- Execution manager handles EasyCrypt proof states

## Common Development Tasks

### Adding a new LSP handler
1. Define message types in `src/lsp/`
2. Add event constructor in `lspManager.ml`
3. Implement handler following SEL event pattern
4. Update protocol documentation

### Debugging
- Enable verbose logging: Set appropriate log levels in driver
- Test specific documents: Use test files in `src/tests/interactive/`
- Trace event flow: Add logging to SEL event handlers

### Dependencies
All OCaml dependencies managed via OPAM and dune. Key libraries:
- `yojson`: JSON parsing for LSP
- `ppx_*`: Various syntax extensions
- `sexplib`: S-expression support

## Development Workflow

### Before Starting Any Feature

1. **Check Current State**:
   ```bash
   git status
   git log --oneline -5
   dune build
   dune runtest
   ```

2. **Create Feature Branch**:
   ```bash
   git checkout -b feature/<roadmap-item>-<description>
   # Example: git checkout -b feature/1.2-parser-integration
   ```

3. **Review Implementation Status**:
   - Check ROADMAP.md for current priorities and dependencies
   - Ensure all prerequisite features are completed
   - Review existing code patterns in similar modules

### Testing Guidelines

**IMPORTANT**: All new features must include comprehensive tests, especially edge cases. Previous tests must ALWAYS pass.

#### Writing Tests

1. **Use PPX Inline Tests**:
   ```ocaml
   let%test "descriptive_test_name" =
     (* Test implementation *)
     expected = actual
   
   let%test_unit "unit_test_name" =
     (* Test with assertions *)
     assert (condition)
   ```

2. **Required Edge Cases to Test**:
   - Empty input/empty state
   - Malformed or invalid input
   - Boundary conditions (start/end of file, max sizes)
   - Unicode and special characters
   - Large inputs (performance testing)
   - Concurrent modifications
   - State transitions and invalidations
   - Error recovery scenarios

3. **Test Organization**:
   ```ocaml
   (* Group related tests *)
   module TestParsing = struct
     let%test "parse_empty_document" = ...
     let%test "parse_invalid_syntax" = ...
     let%test "parse_unicode_identifiers" = ...
   end
   ```

#### Running Tests

```bash
# Run all tests - MUST pass before any commit
dune runtest

# Run specific test module
dune exec ./src/tests/test_<module>.exe

# Run tests in watch mode during development
dune runtest --watch

# Verify no regressions in modified files
git diff --name-only | xargs dune build --force
```

### Code Quality Standards

1. **No Compiler Warnings**: Code must compile with zero warnings
2. **Follow OCaml Conventions**: 
   - Use meaningful variable names
   - Prefer pattern matching over if-then-else
   - Use `|>` for function composition
3. **Document Complex Logic**: Add comments for non-obvious implementations
4. **Maintain Invariants**: Document and preserve module invariants

### Pull Request Process

1. **Ensure All Tests Pass**:
   ```bash
   dune clean && dune build && dune runtest
   ```

2. **Commit with Descriptive Messages**:
   ```bash
   git commit -m "Implement <feature>: <description>
   
   - Add <specific change 1>
   - Fix <specific issue>
   - Test <edge cases covered>"
   ```

3. **Create PR with Template**:
   ```bash
   gh pr create --title "Implement <roadmap-item>: <description>" \
     --body "## Summary
   Implements roadmap item X.Y
   
   ## Testing
   - Added edge case tests for ...
   - All existing tests pass
   - Performance verified on large files"
   ```

### Performance Considerations

- Avoid blocking operations in SEL event handlers
- Use incremental algorithms for document processing
- Test with files >1000 lines
- Profile memory usage for long-running sessions

### Common Pitfalls to Avoid

1. **Don't Block the Event Loop**: Use `Sel.now` for expensive computations
2. **Preserve Document Invariants**: Always validate document state after modifications
3. **Handle All Error Cases**: Never use `assert false` without a TODO comment
4. **Test State Transitions**: Ensure invalid states are impossible
5. **Avoid Global State**: Use the execution manager for state management

## Roadmap and Priorities

See ROADMAP.md for:
- Current implementation status
- Priority ordered feature list
- Dependency graph
- Next available tasks

Always work on the lowest numbered incomplete item from the roadmap that has all dependencies satisfied.