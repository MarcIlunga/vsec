// LSP Service for communicating with the EasyCrypt Language Server
// This service handles LSP requests from the webview to the extension host

export interface LspRequest {
  method: string;
  params: any;
}

export interface LspResponse {
  result?: any;
  error?: {
    code: number;
    message: string;
  };
}

export class LspService {
  private static instance: LspService;
  private messageId = 0;
  private pendingRequests = new Map<number, {
    resolve: (value: any) => void;
    reject: (error: any) => void;
  }>();

  private constructor() {
    // Listen for messages from the extension host
    window.addEventListener('message', (event) => {
      const message = event.data;
      if (message.type === 'lspResponse' && message.id !== undefined) {
        const pending = this.pendingRequests.get(message.id);
        if (pending) {
          this.pendingRequests.delete(message.id);
          if (message.error) {
            pending.reject(new Error(message.error.message));
          } else {
            pending.resolve(message.result);
          }
        }
      }
    });
  }

  public static getInstance(): LspService {
    if (!LspService.instance) {
      LspService.instance = new LspService();
    }
    return LspService.instance;
  }

  public async request(method: string, params: any): Promise<any> {
    return new Promise((resolve, reject) => {
      const id = ++this.messageId;
      
      // Store the pending request
      this.pendingRequests.set(id, { resolve, reject });
      
      // Send request to extension host
      const message = {
        type: 'lspRequest',
        id,
        method,
        params
      };
      
      // Use VS Code's webview API to send message to extension
      if (window.vscode) {
        window.vscode.postMessage(message);
      } else {
        // Fallback for development/testing
        console.warn('VS Code webview API not available, LSP requests will fail');
        reject(new Error('VS Code webview API not available'));
      }
    });
  }

  // Convenience methods for common LSP requests
  public async getSemanticTokens(uri: string, version: number = 1): Promise<any> {
    return this.request('textDocument/semanticTokens/full', {
      textDocument: { uri, version }
    });
  }

  public async getSemanticTokensRange(uri: string, range: any, version: number = 1): Promise<any> {
    return this.request('textDocument/semanticTokens/range', {
      textDocument: { uri, version },
      range
    });
  }

  public async getHover(uri: string, position: any, version: number = 1): Promise<any> {
    return this.request('textDocument/hover', {
      textDocument: { uri, version },
      position
    });
  }

  public async getCompletion(uri: string, position: any, version: number = 1): Promise<any> {
    return this.request('textDocument/completion', {
      textDocument: { uri, version },
      position
    });
  }
}

// Global declaration for VS Code webview API
declare global {
  interface Window {
    vscode: {
      postMessage: (message: any) => void;
    };
  }
}

export default LspService;
