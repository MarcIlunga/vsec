import * as vscode from 'vscode';
import Client from '../client';

interface LemmaSearchResult {
    name: string;
    statement: string;
    module: string;
    relevance: number;
    applicable: boolean;
}

interface TacticSuggestion {
    tactic: string;
    confidence: number;
    reasoning: string;
    example: string;
}

export class ProofSearchProvider {
    
    static async searchApplicableLemmas(goalContext: string): Promise<LemmaSearchResult[]> {
        // In real implementation, this would query EasyCrypt's environment
        // For now, return intelligent mock results based on goal context
        
        const mockLemmas: LemmaSearchResult[] = [
            {
                name: "eq_refl",
                statement: "forall (A : Type) (x : A), x = x",
                module: "Logic.Equality",
                relevance: 0.95,
                applicable: goalContext.includes("=")
            },
            {
                name: "add_comm",
                statement: "forall n m, n + m = m + n",
                module: "Int.Arithmetic", 
                relevance: 0.88,
                applicable: goalContext.includes("+")
            },
            {
                name: "and_intro",
                statement: "forall P Q, P -> Q -> P /\\ Q",
                module: "Logic.Propositional",
                relevance: 0.82,
                applicable: goalContext.includes("/\\")
            },
            {
                name: "forall_intro",
                statement: "forall (A : Type) (P : A -> Prop), (forall x, P x) -> forall x, P x",
                module: "Logic.Quantifiers",
                relevance: 0.90,
                applicable: goalContext.includes("forall")
            }
        ];

        return mockLemmas
            .filter(lemma => lemma.applicable)
            .sort((a, b) => b.relevance - a.relevance)
            .slice(0, 8); // Top 8 results
    }

    static async suggestTactics(goalContext: string, hypotheses: string[]): Promise<TacticSuggestion[]> {
        const suggestions: TacticSuggestion[] = [];

        // Analyze goal context and suggest tactics
        if (goalContext.includes("forall")) {
            suggestions.push({
                tactic: "intros",
                confidence: 0.95,
                reasoning: "Goal contains universal quantification",
                example: "intros x H"
            });
        }

        if (goalContext.includes("=") && hypotheses.some(h => h.includes("="))) {
            suggestions.push({
                tactic: "rewrite",
                confidence: 0.88,
                reasoning: "Goal is equality and equality hypotheses available",
                example: "rewrite H1"
            });
        }

        if (goalContext.includes("/\\")) {
            suggestions.push({
                tactic: "split",
                confidence: 0.85,
                reasoning: "Goal is conjunction",
                example: "split"
            });
        }

        if (hypotheses.length > 0) {
            suggestions.push({
                tactic: "apply",
                confidence: 0.80,
                reasoning: "Hypotheses available for application",
                example: "apply H"
            });
        }

        // Always suggest auto for simple goals
        suggestions.push({
            tactic: "auto",
            confidence: 0.70,
            reasoning: "May solve goal automatically",
            example: "auto"
        });

        return suggestions.sort((a, b) => b.confidence - a.confidence);
    }

    static async showProofSearchPanel(extensionUri: vscode.Uri) {
        const panel = vscode.window.createWebviewPanel(
            'proofSearch',
            '$(search) EasyCrypt Proof Search & Discovery',
            vscode.ViewColumn.Beside,
            {
                enableScripts: true,
                retainContextWhenHidden: true
            }
        );

        const activeEditor = vscode.window.activeTextEditor;
        let goalContext = "x = x"; // Default sample
        let hypotheses: string[] = ["H1 : P", "H2 : Q"];

        if (activeEditor) {
            // In real implementation, extract current goal from cursor position
            const selection = activeEditor.selection;
            const selectedText = activeEditor.document.getText(selection);
            if (selectedText.trim()) {
                goalContext = selectedText.trim();
            }
        }

        // Get intelligent suggestions
        const [lemmas, tactics] = await Promise.all([
            ProofSearchProvider.searchApplicableLemmas(goalContext),
            ProofSearchProvider.suggestTactics(goalContext, hypotheses)
        ]);

        panel.webview.html = ProofSearchProvider.getWebviewContent(lemmas, tactics, goalContext);

        // Handle messages from webview
        panel.webview.onDidReceiveMessage(message => {
            switch (message.type) {
                case 'insertTactic':
                    if (activeEditor) {
                        activeEditor.edit(editBuilder => {
                            editBuilder.insert(activeEditor.selection.active, message.tactic);
                        });
                        Client.writeToVsEcChannel(`🔍 Inserted suggested tactic: ${message.tactic}`);
                    }
                    break;
                
                case 'copyLemma':
                    vscode.env.clipboard.writeText(message.lemma);
                    vscode.window.showInformationMessage(`Copied lemma: ${message.lemma}`);
                    break;

                case 'searchMore':
                    vscode.window.showInformationMessage('Advanced search coming in future versions!');
                    break;
            }
        });
    }

    private static getWebviewContent(lemmas: LemmaSearchResult[], tactics: TacticSuggestion[], goalContext: string): string {
        return `
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>EasyCrypt Proof Search</title>
            <style>
                body {
                    font-family: var(--vscode-font-family);
                    color: var(--vscode-foreground);
                    background: var(--vscode-editor-background);
                    padding: 20px;
                    line-height: 1.6;
                }
                
                .header {
                    border-bottom: 2px solid var(--vscode-focusBorder);
                    padding-bottom: 15px;
                    margin-bottom: 20px;
                }
                
                .goal-context {
                    background: var(--vscode-textBlockQuote-background);
                    border-left: 4px solid var(--vscode-textBlockQuote-border);
                    padding: 12px;
                    margin: 15px 0;
                    font-family: var(--vscode-editor-font-family, monospace);
                    border-radius: 4px;
                }
                
                .section {
                    margin: 25px 0;
                }
                
                .section-title {
                    color: var(--vscode-textLink-foreground);
                    font-size: 18px;
                    font-weight: bold;
                    margin-bottom: 12px;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
                
                .item {
                    background: var(--vscode-editor-inactiveSelectionBackground);
                    border: 1px solid var(--vscode-panel-border);
                    border-radius: 8px;
                    padding: 15px;
                    margin: 10px 0;
                    transition: all 0.2s ease;
                }
                
                .item:hover {
                    background: var(--vscode-list-hoverBackground);
                    border-color: var(--vscode-focusBorder);
                    transform: translateY(-2px);
                    box-shadow: 0 4px 8px rgba(0,0,0,0.1);
                }
                
                .item-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 8px;
                }
                
                .item-name {
                    font-family: var(--vscode-editor-font-family, monospace);
                    color: var(--vscode-textPreformat-foreground);
                    font-weight: bold;
                    font-size: 14px;
                }
                
                .relevance {
                    background: var(--vscode-button-background);
                    color: var(--vscode-button-foreground);
                    padding: 4px 8px;
                    border-radius: 12px;
                    font-size: 11px;
                    font-weight: bold;
                }
                
                .confidence {
                    background: var(--vscode-editorInfo-background);
                    color: var(--vscode-editorInfo-foreground);
                    padding: 4px 8px;
                    border-radius: 12px;
                    font-size: 11px;
                    font-weight: bold;
                }
                
                .statement {
                    font-family: var(--vscode-editor-font-family, monospace);
                    color: var(--vscode-editor-foreground);
                    background: var(--vscode-textPreformat-background);
                    padding: 8px;
                    border-radius: 4px;
                    margin: 8px 0;
                    font-size: 13px;
                }
                
                .reasoning {
                    color: var(--vscode-descriptionForeground);
                    font-style: italic;
                    margin: 5px 0;
                }
                
                .example {
                    font-family: var(--vscode-editor-font-family, monospace);
                    color: var(--vscode-textLink-foreground);
                    background: var(--vscode-textCodeBlock-background);
                    padding: 6px;
                    border-radius: 3px;
                    margin: 5px 0;
                    font-size: 12px;
                }
                
                .module {
                    color: var(--vscode-descriptionForeground);
                    font-size: 12px;
                    margin-top: 5px;
                }
                
                .button {
                    background: var(--vscode-button-background);
                    color: var(--vscode-button-foreground);
                    border: none;
                    padding: 6px 12px;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 12px;
                    margin: 5px 5px 5px 0;
                    transition: all 0.2s;
                }
                
                .button:hover {
                    background: var(--vscode-button-hoverBackground);
                    transform: translateY(-1px);
                }
                
                .search-more {
                    text-align: center;
                    margin: 30px 0;
                }
                
                .search-more button {
                    background: var(--vscode-focusBorder);
                    padding: 12px 24px;
                    font-size: 14px;
                    font-weight: bold;
                }
                
                .empty-state {
                    text-align: center;
                    color: var(--vscode-descriptionForeground);
                    padding: 40px 20px;
                }
                
                .pulse {
                    animation: pulse 2s infinite;
                }
                
                @keyframes pulse {
                    0% { opacity: 1; }
                    50% { opacity: 0.7; }
                    100% { opacity: 1; }
                }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>EasyCrypt Proof Search & Discovery</h1>
                <p>Intelligent lemma search and tactic suggestions for your proofs</p>
                
                <div class="goal-context">
                    <strong>Current Goal Context:</strong><br>
                    <code>${goalContext}</code>
                </div>
            </div>

            <div class="section">
                <h2 class="section-title">
                    Smart Tactic Suggestions
                </h2>
                ${tactics.length > 0 ? tactics.map(tactic => `
                    <div class="item">
                        <div class="item-header">
                            <span class="item-name">${tactic.tactic}</span>
                            <span class="confidence">${Math.round(tactic.confidence * 100)}% confidence</span>
                        </div>
                        <div class="reasoning">${tactic.reasoning}</div>
                        <div class="example">Example: ${tactic.example}</div>
                        <button class="button" onclick="insertTactic('${tactic.tactic}')">
                            Insert Tactic
                        </button>
                    </div>
                `).join('') : '<div class="empty-state">No specific tactic suggestions for this goal.</div>'}
            </div>

            <div class="section">
                <h2 class="section-title">
                    Applicable Lemmas & Theorems
                </h2>
                ${lemmas.length > 0 ? lemmas.map(lemma => `
                    <div class="item">
                        <div class="item-header">
                            <span class="item-name">${lemma.name}</span>
                            <span class="relevance">${Math.round(lemma.relevance * 100)}% relevance</span>
                        </div>
                        <div class="statement">${lemma.statement}</div>
                        <div class="module">${lemma.module}</div>
                        <button class="button" onclick="insertTactic('apply ${lemma.name}')">
                            Apply Lemma
                        </button>
                        <button class="button" onclick="copyLemma('${lemma.name}')">
                            Copy Name
                        </button>
                    </div>
                `).join('') : '<div class="empty-state">No applicable lemmas found for this goal context.</div>'}
            </div>

            <div class="search-more">
                <button class="button pulse" onclick="searchMore()">
                    Advanced Search & Discovery
                </button>
            </div>

            <script>
                const vscode = acquireVsCodeApi();

                function insertTactic(tactic) {
                    vscode.postMessage({
                        type: 'insertTactic',
                        tactic: tactic + ' '
                    });
                }

                function copyLemma(lemma) {
                    vscode.postMessage({
                        type: 'copyLemma', 
                        lemma: lemma
                    });
                }

                function searchMore() {
                    vscode.postMessage({
                        type: 'searchMore'
                    });
                }
            </script>
        </body>
        </html>`;
    }
}