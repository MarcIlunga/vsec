# VsEc Implementation Roadmap

## Overview
This roadmap outlines the implementation plan for VsEc (EasyCrypt Language Server), including dependencies, priorities, and development guidelines.

## Implementation Status Summary

### ✅ Completed Features
- **Core LSP Infrastructure**: Message handling, JSON-RPC protocol
- **Document Management**: Text synchronization, incremental updates
- **SEL Event System**: Non-blocking I/O, event dispatch
- **Basic LSP Lifecycle**: Initialize, shutdown, document open/close
- **Custom Protocol Extensions**: Navigation commands (stepForward, stepBackward, interpretToPoint)
- **Basic Hover Support**: Word-at-position lookup (needs enhancement)

### 🚧 Partially Implemented
- **Syntax Highlighting**: Token-based system exists, needs EasyCrypt tokens
- **Diagnostics Publishing**: Framework exists, needs EasyCrypt errors
- **State Management**: Uses EcScope but lacks full integration

### ❌ Not Implemented
- **EasyCrypt Parser**: Stubbed at `src/dm/document.ml:350`
- **Code Completion**: Empty implementation at `src/driver/lspManager.ml:285`
- **Go to Definition**: No implementation
- **Find References**: No implementation
- **Document Symbols**: No implementation
- **Code Actions**: No implementation

## Priority Implementation Plan

### Phase 1: Foundation (Critical Prerequisites)

#### 1.1 Initialize EasyCrypt Submodule 🔴
**Priority**: P0 - Blocker
**Dependencies**: None
**Location**: `src/easycrypt/`
**Tasks**:
- Initialize git submodule: `git submodule update --init --recursive`
- Verify EasyCrypt library builds correctly
- Update dune files to properly link EasyCrypt libraries
- Document available EasyCrypt modules and APIs

#### 1.2 EasyCrypt Parser Integration 🔴
**Priority**: P0 - Blocker
**Dependencies**: 1.1
**Location**: `src/dm/document.ml:350`
**Tasks**:
- Implement `parse_more` function using `EcParser`
- Create `parsed_ast` structures from EasyCrypt AST
- Handle parse errors with proper locations
- Map EasyCrypt tokens to syntax highlighting categories
- Implement sentence boundary detection

### Phase 2: Core Functionality

#### 2.1 Execution Engine Integration 🔴
**Priority**: P1 - Critical
**Dependencies**: 1.1, 1.2
**Location**: `src/dm/executionManager.ml`
**Tasks**:
- Replace Coq execution with EasyCrypt execution
- Implement `execute_sentence` for EasyCrypt
- Handle proof state management
- Integrate error feedback
- Support tactic execution

#### 2.2 Error Diagnostics 🔴
**Priority**: P1 - Critical
**Dependencies**: 1.2, 2.1
**Location**: `src/dm/documentManager.ml`
**Tasks**:
- Convert EasyCrypt errors to LSP diagnostics
- Map error locations correctly
- Implement severity levels
- Handle parse, type, and execution errors
- Support warning messages

### Phase 3: Productivity Features

#### 3.1 Code Completion 🟡
**Priority**: P2 - High
**Dependencies**: 1.2, 2.1
**Location**: `src/driver/lspManager.ml:285`
**Tasks**:
- Implement context analysis for completion position
- Query available tactics at proof position
- Complete identifiers (lemmas, modules, types)
- Add keyword completion
- Implement completion item details and documentation

#### 3.2 Go to Definition 🟡
**Priority**: P2 - High
**Dependencies**: 1.2
**Location**: New implementation needed
**Tasks**:
- Implement symbol table building during parsing
- Add definition location tracking
- Handle cross-file navigation
- Support various definition types (lemmas, modules, types)

#### 3.3 Hover Information Enhancement 🟡
**Priority**: P2 - High
**Dependencies**: 1.2, 2.1
**Location**: `src/driver/lspManager.ml` (enhance existing)
**Tasks**:
- Add type information display
- Show proof state at position
- Include documentation strings
- Display tactic help

### Phase 4: Advanced Features

#### 4.1 Find References 🟡
**Priority**: P3 - Medium
**Dependencies**: 3.2
**Location**: New implementation needed
**Tasks**:
- Build reference index during parsing
- Implement workspace-wide search
- Handle renaming support
- Optimize for large codebases

#### 4.2 Document Symbols 🟢
**Priority**: P3 - Medium
**Dependencies**: 1.2
**Location**: New implementation needed
**Tasks**:
- Extract document structure during parsing
- Create hierarchical symbol tree
- Support filtering and navigation
- Implement workspace symbols

#### 4.3 Code Actions 🟢
**Priority**: P3 - Medium
**Dependencies**: 2.1, 2.2
**Location**: New implementation needed
**Tasks**:
- Implement quick fixes for common errors
- Add auto-import functionality
- Create proof skeleton generation
- Support tactic suggestions

### Phase 5: Quality & Testing

#### 5.1 Test Infrastructure 🟡
**Priority**: P2 - High (continuous)
**Dependencies**: Each feature
**Location**: `src/tests/`
**Tasks**:
- Create EasyCrypt test files (`.ec`)
- Implement LSP protocol tests
- Add parser unit tests
- Create integration test suite
- Set up CI/CD pipeline

## Development Guidelines for Claude

### Before Starting Any Task

1. **Check Current State**:
   ```bash
   git status
   git log --oneline -5
   dune build
   dune runtest
   ```

2. **Create Feature Branch**:
   ```bash
   git checkout -b feature/<roadmap-item-number>-<short-description>
   # Example: git checkout -b feature/1.2-parser-integration
   ```

3. **Review Implementation Status**:
   - Read this ROADMAP.md for context
   - Check CLAUDE.md for development commands
   - Review existing code in relevant modules
   - Identify all dependencies are completed

### Implementation Process

1. **Understand the Context**:
   - Study existing VSCoq implementation for patterns
   - Review EasyCrypt documentation for language features
   - Examine how similar features work in the codebase

2. **Plan the Implementation**:
   - Create detailed task breakdown using TodoWrite
   - Identify all files that need modification
   - Plan test cases including edge cases

3. **Implement with Tests**:
   ```ocaml
   (* Always include inline tests *)
   let%test "edge_case_empty_input" =
     parse_more empty_state "" = ([], [])
   
   let%test "edge_case_invalid_syntax" =
     match parse_more state "lemma" with
     | _, err :: _ -> true
     | _ -> false
   ```

4. **Edge Cases to Always Test**:
   - Empty input
   - Malformed input
   - Boundary conditions (start/end of file)
   - Unicode and special characters
   - Large files (performance)
   - Concurrent modifications
   - Invalid state transitions

5. **Verify All Tests Pass**:
   ```bash
   # Run all tests
   dune runtest
   
   # Run specific test
   dune exec ./src/tests/test_<module>.exe
   
   # Ensure no regressions
   git diff --name-only | xargs dune build --force
   ```

6. **Code Quality Checks**:
   - No compiler warnings
   - Follow OCaml conventions
   - Document complex logic
   - Update relevant documentation

### Creating Pull Request

1. **Final Verification**:
   ```bash
   # Clean build
   dune clean && dune build
   
   # All tests pass
   dune runtest
   
   # No uncommitted changes except feature
   git status
   ```

2. **Commit with Descriptive Message**:
   ```bash
   git add -A
   git commit -m "Implement <feature>: <description>

   - Add <specific change 1>
   - Implement <specific change 2>
   - Test <edge cases covered>
   
   Closes #<issue-number>"
   ```

3. **Create Pull Request**:
   ```bash
   git push -u origin feature/<branch-name>
   gh pr create --title "Implement <roadmap-item>: <description>" \
     --body "## Summary
   Implements roadmap item <number>: <description>
   
   ## Changes
   - <change 1>
   - <change 2>
   
   ## Testing
   - Added tests for <edge case 1>
   - Added tests for <edge case 2>
   - All existing tests pass
   
   ## Checklist
   - [ ] All tests pass
   - [ ] No compiler warnings
   - [ ] Documentation updated
   - [ ] Edge cases tested"
   ```

### Next Steps Selection

1. **Choose Next Item**:
   - Select lowest incomplete item from roadmap
   - Verify all dependencies are complete
   - Check no one else is working on it

2. **Update Roadmap**:
   - Mark item as "🚧 In Progress"
   - Update completion status after merge
   - Add any discovered dependencies

## Dependency Graph

```
1.1 Initialize Submodule
    ├── 1.2 Parser Integration
    │   ├── 2.2 Error Diagnostics
    │   ├── 3.1 Code Completion
    │   ├── 3.2 Go to Definition
    │   │   └── 4.1 Find References
    │   └── 4.2 Document Symbols
    └── 2.1 Execution Engine
        ├── 2.2 Error Diagnostics
        ├── 3.1 Code Completion
        ├── 3.3 Hover Enhancement
        └── 4.3 Code Actions

5.1 Test Infrastructure (continuous, parallels all development)
```

## Success Metrics

Each implementation should:
1. Have >90% test coverage for new code
2. Pass all existing tests without modification
3. Handle all identified edge cases
4. Perform adequately on large files (>1000 lines)
5. Follow established code patterns
6. Include inline documentation

## Notes for Future Implementers

- The SEL event system is central - understand it before implementing async features
- EasyCrypt's proof state is more complex than typical LSP servers handle
- Performance matters - avoid blocking operations in event handlers
- The document manager maintains critical invariants - study before modifying
- Always test with real EasyCrypt files, not just unit tests