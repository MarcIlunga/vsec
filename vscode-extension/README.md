# VsEc - EasyCrypt Language Support

Rich language support for EasyCrypt with semantic highlighting, completion, and proof assistance.

## Features

- **Semantic Highlighting**: Advanced syntax highlighting powered by the EasyCrypt language server
- **Code Completion**: Intelligent completion for EasyCrypt keywords, tactics, and context-aware suggestions
- **Hover Information**: Get detailed information about symbols and constructs
- **Go to Definition**: Navigate to symbol definitions
- **Find References**: Find all references to symbols
- **Document Symbols**: Navigate through document structure
- **Proof Navigation**: Step-by-step proof execution and interpretation

## Commands

- `VsEc: Restart Language Server` - Restart the language server
- `VsEc: Interpret to Current Position` - Execute proof up to cursor position
- `VsEc: Interpret to End` - Execute entire document
- `VsEc: Step Backward` - Step back in proof execution
- `VsEc: Step Forward` - Step forward in proof execution

## Configuration

- `vsec.serverPath`: Path to the VsEc language server executable
- `vsec.enableSemanticHighlighting`: Enable semantic highlighting (default: true)
- `vsec.trace.server`: Set server communication trace level

## Installation

1. Ensure you have the VsEc language server compiled and available
2. Install this extension from the VSIX package
3. Configure the server path in VSCode settings if not using default paths

## Requirements

- VsEc language server (built from the VsEc project)
- EasyCrypt proof assistant
- OCaml and associated dependencies (for language server)

## Language Server Integration

This extension works with the VsEc language server, which provides:

- Parse and validation of EasyCrypt files
- Semantic analysis and token classification
- Integration with EasyCrypt's proof engine
- Real-time feedback and diagnostics

## Semantic Highlighting

The extension provides rich semantic highlighting that goes beyond basic syntax coloring:

- **Keywords**: Core EasyCrypt language constructs (lemma, theorem, proof, etc.)
- **Tactics**: Proof tactics (trivial, apply, rewrite, etc.)
- **Modules**: Module names and references
- **Theories**: Theory definitions and imports
- **Operators**: User-defined operators
- **Predicates**: User-defined predicates
- **Goals**: Current proof goals
- **Hypotheses**: Proof context and hypotheses

## Development

To build from source:

```bash
npm install
npm run compile
npm run package
```

## License

MIT License - see LICENSE file for details.