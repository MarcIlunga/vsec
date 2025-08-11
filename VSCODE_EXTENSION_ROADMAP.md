# VSCode Extension Roadmap for VsEc EasyCrypt

## 📊 **Current State Analysis**

### ✅ **What We Have**
- **Language Server**: Fully implemented with comprehensive LSP features
  - Code completion (60+ keywords/tactics)
  - Go to definition
  - Hover information 
  - Document symbols
  - Find references
  - Error diagnostics
- **Language Server Executable**: `src/_build/default/driver/ecLsp.exe`
- **Launch Script**: `run-vsec-lsp.sh`
- **EasyCrypt Examples**: Extensive `.ec` files in `src/easycrypt/`

### ❌ **What's Missing**
- **VSCode Extension Client**: No extension project exists
- **Language Definition**: No syntax highlighting or language configuration
- **File Associations**: No `.ec` file type registration  
- **Extension Package**: No `package.json` for VSCode extension
- **Language Client**: No LSP client to connect to our server
- **Extension Manifest**: No extension metadata or activation events

## 🎯 **VSCode Extension Roadmap**

### **Phase 1: Foundation (P0 - Critical)**

#### 1.1 **Initialize Extension Project** 
- Create VSCode extension directory structure
- Set up `package.json` with extension metadata
- Configure TypeScript build system
- Add development dependencies (vscode API, language client)

#### 1.2 **Language Support (Semantic Focus)**
- Define EasyCrypt language configuration  
- Set up file associations for `.ec` and `.eca` files
- Add basic language features (commenting, brackets, etc.)
- **Minimal TextMate grammar** (only for fallback when server unavailable)
- **Focus on semantic highlighting** via language server

#### 1.3 **Language Server Integration**
- Implement VSCode Language Client 
- Configure server connection and lifecycle
- Set up server executable path resolution
- Handle server startup and error handling

### **Phase 2: Semantic Features (P1 - High Priority)**

#### 2.1 **Semantic Highlighting Implementation**
- **Server-side**: Implement semantic tokens provider in language server
- **Client-side**: Enable semantic highlighting in VSCode client
- **Token types**: Keywords, identifiers, types, modules, tactics, etc.
- **Scope-aware coloring**: Local vs global, proof context, module scope
- **Proof state highlighting**: Goals, hypotheses, tactics

#### 2.2 **Core LSP Features**
- Enable code completion with IntelliSense  
- Implement go to definition navigation
- Configure hover information display
- Set up document symbols in outline view
- Enable find references functionality

#### 2.3 **Advanced Semantic Features**
- **Context-aware highlighting**: Different colors for same identifier in different scopes
- **Proof state visualization**: Highlight current goal, available tactics
- **Error-aware highlighting**: Mark problematic code before diagnostics
- **Module-aware coloring**: Different colors for imported vs local definitions

### **Phase 3: User Experience (P2 - Medium Priority)**

#### 3.1 **Extension Configuration**
- Add extension settings/preferences
- Configure language server options
- Set up workspace-specific settings
- Add configuration validation

#### 3.2 **Commands and Menus**
- Add extension commands (restart server, etc.)
- Create context menu items
- Add command palette entries
- Set up keyboard shortcuts

#### 3.3 **Status and Feedback**
- Language server status indicator
- Progress notifications
- Error reporting and logging
- Debug output channels

### **Phase 4: Polish and Distribution (P3 - Nice to Have)**

#### 4.1 **Documentation and Help**
- Extension README and documentation
- Usage examples and tutorials
- Troubleshooting guides
- API documentation

#### 4.2 **Testing and Quality**
- Extension unit tests
- Integration tests with language server  
- Manual testing scenarios
- Performance optimization

#### 4.3 **Packaging and Distribution**
- Create VSIX package
- Set up extension marketplace metadata
- Add extension icon and branding
- Prepare for marketplace publication

## 🚀 **Implementation Priority**

### **Immediate (This Session)**
1. **Extension Scaffolding** - Basic project structure
2. **Language Definition** - Syntax highlighting and file associations  
3. **LSP Integration** - Connect to our existing language server
4. **Core Features** - Enable completion, hover, definition
5. **VSIX Packaging** - Create distributable extension

### **Future Enhancements**
1. **Advanced Features** - Code actions, formatting, advanced diagnostics
2. **UX Polish** - Configuration, commands, status indicators
3. **Documentation** - User guides and API docs
4. **Testing** - Comprehensive test suite

## 📋 **Technical Requirements**

### **Dependencies**
- `@types/vscode` - VSCode API types
- `vscode-languageclient` - LSP client implementation
- `typescript` - TypeScript compiler
- `@vscode/vsce` - Extension packaging tool

### **File Structure**
```
/
├── package.json              # Extension manifest
├── src/
│   ├── extension.ts          # Main extension entry point
│   ├── languageClient.ts     # LSP client implementation
│   └── syntaxes/
│       └── easycrypt.tmLanguage.json  # Syntax highlighting
├── language-configuration.json  # Language config
├── README.md                 # Extension documentation
└── .vscodeignore            # Files to exclude from package
```

### **Key Extension Features**
- **Language ID**: `easycrypt`
- **File Extensions**: `.ec`, `.eca`  
- **Server Command**: Path to `run-vsec-lsp.sh`
- **Activation Events**: `onLanguage:easycrypt`

## 🎯 **Success Criteria**

1. **Basic Functionality**: Extension loads and connects to language server
2. **Syntax Highlighting**: EasyCrypt code is properly highlighted
3. **LSP Features**: All server features work in VSCode
4. **File Association**: `.ec` files automatically activate extension
5. **VSIX Package**: Extension can be installed from `.vsix` file

## 🔄 **Development Workflow**

1. **Development**: Use VSCode Extension Development Host for testing
2. **Testing**: Manual testing with EasyCrypt examples
3. **Packaging**: Build VSIX with `vsce package`
4. **Installation**: Install and test packaged extension
5. **Distribution**: Ready for marketplace or manual distribution

---

**Status**: 🏗️ **Ready for Implementation**  
**Server**: ✅ Complete and tested  
**Client**: 🚧 To be implemented  
**Timeline**: Single session implementation possible