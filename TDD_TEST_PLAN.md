# VsEc TDD Test Plan - Proof General Feature Parity

## Overview
This document outlines comprehensive tests to ensure VsEc matches or exceeds Proof General's EasyCrypt interactive proving capabilities.

## Core Proof General Features to Test

### 1. Interactive Proof Navigation
- **Assert Until Point** (C-c C-n)
  - Execute script up to cursor position
  - Handle partial commands
  - Error recovery
- **Undo Last Command** (C-c C-u) 
  - Retract one command
  - Restore previous proof state
- **Retract Until Point** (C-c C-r)
  - Retract back to cursor
  - Maintain proof context
- **Step Forward/Backward**
  - Single step execution
  - Command-by-command navigation

### 2. Proof State Management
- **Goal Display**
  - Current goals rendering
  - Hypothesis display
  - Progress indication
- **Error Highlighting**
  - Syntax error detection
  - Proof error positioning
  - Error message display
- **Context Switching**
  - Multiple document support
  - Buffer synchronization

### 3. Electric Features
- **Electric Terminator**
  - Auto-execution on '.'
  - Context awareness (comments/strings)
- **Smart Indentation**
  - Proof block indentation
  - Tactic alignment

### 4. Advanced Features
- **Completion**
  - Tactic completion
  - Symbol completion
  - Context-aware suggestions
- **Syntax Highlighting**
  - EasyCrypt keywords
  - Proof states
  - Comments and strings

## Test Categories

### A. Unit Tests (src/tests/)
Focus on core functionality with isolated components.

### B. Integration Tests (python scripts)
Test LSP protocol and full workflow.

### C. End-to-End Tests (.ec files)
Real EasyCrypt proof scenarios.

### D. Performance Tests
Large file handling and responsiveness.

## Test File Organization

```
tests/
├── unit/                    # OCaml unit tests
│   ├── test_document_manager.ml
│   ├── test_execution_manager.ml
│   └── test_lsp_protocol.ml
├── integration/             # Python LSP tests
│   ├── test_interactive_proving.py
│   ├── test_navigation.py
│   ├── test_completion.py
│   └── test_error_handling.py
├── e2e/                     # EasyCrypt scenario tests
│   ├── basic_lemma.ec
│   ├── complex_proof.ec
│   ├── module_system.ec
│   └── error_scenarios.ec
└── performance/
    ├── large_file_test.ec
    └── responsiveness_test.py
```

## Specific Test Cases

### Interactive Navigation Tests
1. **Assert Until Point**
   ```python
   def test_assert_until_point():
       # Load EC file with multiple lemmas
       # Position cursor mid-proof
       # Send interpretToPoint
       # Verify goals updated correctly
   ```

2. **Step Forward/Backward**
   ```python
   def test_step_navigation():
       # Test stepForward command
       # Test stepBackward command
       # Verify cursor movement and goals
   ```

### Error Handling Tests
3. **Syntax Error Recovery**
   ```python
   def test_syntax_error_handling():
       # Send malformed EC code
       # Verify error highlighting
       # Test error message display
   ```

### Completion Tests
4. **Context-Aware Completion**
   ```python
   def test_completion_features():
       # Test tactic completion in proof context
       # Test symbol completion in definitions
       # Test module system completion
   ```

## Success Criteria

### Minimum Viable Product (MVP)
- [ ] Basic assert/undo/retract functionality
- [ ] Goal display in proof view
- [ ] Error highlighting and messages
- [ ] Basic completion for tactics

### Feature Parity with Proof General
- [ ] All PG interactive commands working
- [ ] Electric terminator support
- [ ] Advanced completion features
- [ ] Multiple document support

### Enhanced Features (Beyond PG)
- [ ] Real-time goal updates
- [ ] Enhanced error messages
- [ ] Performance optimizations
- [ ] Modern UI/UX improvements

## Implementation Strategy

1. **Test-First Development**: Write failing tests for each PG feature
2. **Incremental Implementation**: Implement features to make tests pass
3. **Continuous Validation**: Run full test suite on every change
4. **Performance Monitoring**: Track response times and memory usage
5. **User Feedback Integration**: Collect and address real-world usage patterns

## Automation

### CI/CD Pipeline
- Run unit tests on every commit
- Run integration tests on PR creation
- Performance regression testing
- Automated test result reporting

### Test Execution
```bash
# Run all tests
make test

# Run specific test category
make test-unit
make test-integration  
make test-e2e

# Run performance benchmarks
make test-performance
```
