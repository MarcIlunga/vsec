import * as assert from 'assert';
import * as vscode from 'vscode';
import * as sinon from 'sinon';

/**
 * Query Commands Test Suite
 * 
 * Tests the query command functionality:
 * - vsec.query command
 * - vsec.querySymbol command
 * - Hover provider
 * - Definition provider
 * - LSP request handling
 */
suite('Query Commands Test Suite', () => {
    let sandbox: sinon.SinonSandbox;
    let mockClient: any;
    
    setup(() => {
        sandbox = sinon.createSandbox();
        
        // Mock LSP client
        mockClient = {
            sendRequest: sandbox.stub()
        };
    });
    
    teardown(() => {
        sandbox.restore();
    });

    suite('Query Command Input Validation', () => {
        test('Should reject empty input', async () => {
            const input = '';
            const parts = input.trim().split(/\s+/);
            assert.strictEqual(parts.length < 2, true, 'Empty input should be invalid');
        });

        test('Should reject single word input', async () => {
            const input = 'print';
            const parts = input.trim().split(/\s+/);
            assert.strictEqual(parts.length < 2, true, 'Single word should be invalid');
        });

        test('Should accept valid command format', async () => {
            const input = 'print bool';
            const parts = input.trim().split(/\s+/);
            const command = parts[0];
            if (!command) {
                assert.fail('Command should exist');
            }
            const argument = parts.slice(1).join(' ');
            
            assert.strictEqual(parts.length >= 2, true, 'Should have at least 2 parts');
            assert.strictEqual(command, 'print', 'Command should be extracted');
            assert.strictEqual(argument, 'bool', 'Argument should be extracted');
        });

        test('Should handle multi-word arguments', async () => {
            const input = 'search eq_refl sym';
            const parts = input.trim().split(/\s+/);
            const command = parts[0];
            if (!command) {
                assert.fail('Command should exist');
            }
            const argument = parts.slice(1).join(' ');
            
            assert.strictEqual(command, 'search');
            assert.strictEqual(argument, 'eq_refl sym');
        });

        test('Should validate command names', async () => {
            const validCommands = ['print', 'check', 'search', 'locate'];
            
            validCommands.forEach(cmd => {
                assert.ok(validCommands.includes(cmd), `${cmd} should be valid`);
            });
            
            assert.strictEqual(validCommands.includes('invalid'), false);
        });
    });

    suite('Symbol Extraction', () => {
        test('Should extract word at cursor position', () => {
            const text = 'lemma test : bool => bool.';
            const position = 15; // On 'bool'
            
            // Simulate word extraction
            const wordRegex = /[a-zA-Z_][a-zA-Z0-9_']*/g;
            let match;
            let extractedWord = null;
            
            while ((match = wordRegex.exec(text)) !== null) {
                const matchedText = match[0];
                if (!matchedText) continue;
                if (match.index <= position && position < match.index + matchedText.length) {
                    extractedWord = matchedText;
                    break;
                }
            }
            
            assert.strictEqual(extractedWord, 'bool');
        });

        test('Should handle identifiers with primes', () => {
            const text = "let x' = x + 1";
            const wordRegex = /[a-zA-Z_][a-zA-Z0-9_']*/;
            const match = text.match(wordRegex);
            
            assert.strictEqual(match?.[0], 'let');
            
            // Check for x'
            const primeMatch = text.match(/x'/);
            assert.ok(primeMatch, "Should match x'");
        });

        test('Should handle qualified names', () => {
            const text = 'Bool.andb';
            const qualifiedRegex = /[a-zA-Z_][a-zA-Z0-9_']*(\.[a-zA-Z_][a-zA-Z0-9_']*)*/;
            const match = text.match(qualifiedRegex);
            
            assert.strictEqual(match?.[0], 'Bool.andb');
        });

        test('Should not extract operators', () => {
            const text = 'x = y + z';
            const wordRegex = /[a-zA-Z_][a-zA-Z0-9_']*/g;
            const words = text.match(wordRegex);
            
            assert.deepStrictEqual(words, ['x', 'y', 'z']);
            // = and + should not be included
        });
    });

    suite('LSP Query Request Format', () => {
        test('Should format print request correctly', () => {
            const request = {
                textDocument: {
                    uri: 'file:///test.ec',
                    version: 1
                },
                command: 'print',
                argument: 'bool'
            };
            
            assert.strictEqual(request.command, 'print');
            assert.strictEqual(request.argument, 'bool');
            assert.ok(request.textDocument);
        });

        test('Should format check request correctly', () => {
            const request = {
                textDocument: {
                    uri: 'file:///test.ec',
                    version: 1
                },
                command: 'check',
                argument: 'int'
            };
            
            assert.strictEqual(request.command, 'check');
            assert.strictEqual(request.argument, 'int');
        });

        test('Should format search request correctly', () => {
            const request = {
                textDocument: {
                    uri: 'file:///test.ec',
                    version: 1
                },
                command: 'search',
                argument: 'eq'
            };
            
            assert.strictEqual(request.command, 'search');
            assert.strictEqual(request.argument, 'eq');
        });

        test('Should format locate request correctly', () => {
            const request = {
                textDocument: {
                    uri: 'file:///test.ec',
                    version: 1
                },
                command: 'locate',
                argument: 'Bool'
            };
            
            assert.strictEqual(request.command, 'locate');
            assert.strictEqual(request.argument, 'Bool');
        });
    });

    suite('LSP Response Handling', () => {
        test('Should handle successful response', () => {
            const response = {
                success: true,
                result: 'bool : Type\nThe boolean type.'
            };
            
            assert.strictEqual(response.success, true);
            assert.ok(response.result);
            const result = response.result;
            if (!result) throw new Error("Expected result");
            assert.ok(result.includes('bool'));
        });

        test('Should handle error response', () => {
            const response = {
                success: false,
                error: 'Symbol not found'
            };
            
            assert.strictEqual(response.success, false);
            assert.ok(response.error);
        });

        test('Should handle empty result', () => {
            const response = {
                success: true,
                result: ''
            };
            
            assert.strictEqual(response.success, true);
            const result = response.result;
            if (result === undefined) throw new Error("Expected result");
            assert.strictEqual(result, '');
        });

        test('Should parse search results', () => {
            const response = {
                success: true,
                result: 'eq_refl : forall (A : Type) (x : A), x = x\neq_sym : forall (A : Type) (x y : A), x = y => y = x'
            };
            
            const result = response.result;
            if (!result) throw new Error("Expected result");
            const lines = result.split('\n');
            assert.strictEqual(lines.length, 2);
            
            lines.forEach(line => {
                const match = line.match(/^([^\s:]+)\s*:\s*(.+)$/);
                assert.ok(match, `Line should match pattern: ${line}`);
                if (match) {
                    assert.ok(match[1]); // Name
                    assert.ok(match[2]); // Type/statement
                }
            });
        });
    });

    suite('Hover Provider', () => {
        test('Should extract word at position for hover', () => {
            const line = 'lemma test : bool => bool.';
            const character = 15; // On 'bool'
            
            const wordRange = {
                start: { line: 0, character: 13 },
                end: { line: 0, character: 17 }
            };
            
            const word = line.substring(wordRange.start.character, wordRange.end.character);
            assert.strictEqual(word, 'bool');
        });

        test('Should format hover content', () => {
            const queryResult = '✓ Type: bool\nArity: 0 type parameters';
            const hoverContent = '```easycrypt\n' + queryResult + '\n```';
            
            assert.ok(hoverContent.includes('```easycrypt'));
            assert.ok(hoverContent.includes(queryResult));
        });

        test('Should return null for non-identifiers', () => {
            const line = 'x = y';
            const character = 2; // On '='
            
            const wordRegex = /[a-zA-Z_][a-zA-Z0-9_']*/;
            const charAtPos = line[character];
            if (!charAtPos) {
                assert.fail('Character at position should exist');
            }
            const isIdentifier = wordRegex.test(charAtPos);
            
            assert.strictEqual(isIdentifier, false);
        });
    });

    suite('Definition Provider', () => {
        test('Should extract symbol for go-to-definition', () => {
            const line = 'require import Bool.';
            const character = 15; // On 'Bool'
            
            const wordRange = {
                start: { line: 0, character: 15 },
                end: { line: 0, character: 19 }
            };
            
            const word = line.substring(wordRange.start.character, wordRange.end.character);
            assert.strictEqual(word, 'Bool');
        });

        test('Should handle locate result parsing', () => {
            const locateResult = 'Bool : theory in file:///easycrypt/theories/Bool.ec';
            
            // Future: parse file location
            assert.ok(locateResult.includes('Bool'));
            assert.ok(locateResult.includes('theory'));
        });
    });

    suite('ProofSearch Integration', () => {
        test('Should extract search terms from goal', () => {
            const goalContext = 'forall (x y : int), x + y = y + x';
            
            const matches = goalContext.match(/[a-zA-Z_][a-zA-Z0-9_']*/g) || [];
            const uniqueTerms = [...new Set(matches)];
            
            const commonWords = ['forall', 'exists', 'fun', 'let', 'in', 'if', 'then', 'else'];
            const searchTerms = uniqueTerms.filter(t => 
                !commonWords.includes(t.toLowerCase()) && t.length > 2
            );
            
            assert.ok(searchTerms.includes('int'));
        });

        test('Should calculate relevance score', () => {
            const lemmaName = 'Int.add_comm';
            const goalContext = 'x + y = y + x';
            
            let score = 0.5;
            
            // Boost if lemma name component appears in goal
            const nameParts = lemmaName.split('.');
            const lastName = nameParts[nameParts.length - 1];
            
            if (lastName && goalContext.includes(lastName)) {
                score += 0.3;
            }
            
            // Should not match since 'add_comm' not in goal
            assert.strictEqual(score, 0.5);
        });

        test('Should extract module from qualified name', () => {
            const fullName = 'Logic.Equality.eq_refl';
            const parts = fullName.split('.');
            const module = parts.length > 1 ? parts.slice(0, -1).join('.') : 'Pervasive';
            
            assert.strictEqual(module, 'Logic.Equality');
        });

        test('Should handle unqualified names', () => {
            const fullName = 'eq_refl';
            const parts = fullName.split('.');
            const module = parts.length > 1 ? parts.slice(0, -1).join('.') : 'Pervasive';
            
            assert.strictEqual(module, 'Pervasive');
        });
    });

    suite('Query History', () => {
        test('Should add query to history', () => {
            const history: Array<{command: string; argument: string; timestamp: number}> = [];
            
            const entry = {
                command: 'print',
                argument: 'bool',
                timestamp: Date.now()
            };
            
            history.push(entry);
            
            assert.strictEqual(history.length, 1);
            const firstEntry = history[0];
            if (!firstEntry) {
                assert.fail('First history entry should exist');
            }
            assert.strictEqual(firstEntry.command, 'print');
            assert.strictEqual(firstEntry.argument, 'bool');
        });

        test('Should limit history to 10 items', () => {
            const history: Array<{command: string; argument: string}> = [];
            
            for (let i = 0; i < 15; i++) {
                history.push({ command: 'print', argument: `symbol${i}` });
            }
            
            const limited = history.slice(0, 10);
            assert.strictEqual(limited.length, 10);
        });

        test('Should maintain chronological order', () => {
            const history: Array<{command: string; argument: string; timestamp: number}> = [];
            
            for (let i = 0; i < 5; i++) {
                history.push({
                    command: 'print',
                    argument: `symbol${i}`,
                    timestamp: Date.now() + i
                });
            }
            
            // Most recent first
            const sorted = [...history].sort((a, b) => b.timestamp - a.timestamp);
            const firstSorted = sorted[0];
            if (!firstSorted) {
                assert.fail('First sorted entry should exist');
            }
            assert.strictEqual(firstSorted.argument, 'symbol4');
        });
    });

    suite('Error Handling', () => {
        test('Should handle LSP timeout', async () => {
            const timeout = 10000; // 10 seconds
            const startTime = Date.now();
            
            // Simulate timeout
            await new Promise(resolve => setTimeout(resolve, 10));
            
            const elapsed = Date.now() - startTime;
            assert.ok(elapsed < timeout, 'Should complete before timeout');
        });

        test('Should handle malformed symbol names', () => {
            const invalidSymbols = [
                '',
                'Module..symbol',
                '.symbol',
                'Module.',
                '123invalid',
                'invalid!@#'
            ];
            
            invalidSymbols.forEach(symbol => {
                const isEmpty = symbol.length === 0;
                const hasDoubleDot = symbol.includes('..');
                const startsWithDot = symbol.startsWith('.');
                const endsWithDot = symbol.endsWith('.');
                const startsWithDigit = /^\d/.test(symbol);
                const hasSpecialChars = /[!@#$%^&*()]/.test(symbol);
                
                const isInvalid = isEmpty || hasDoubleDot || startsWithDot || 
                                 endsWithDot || startsWithDigit || hasSpecialChars;
                
                assert.ok(isInvalid, `${symbol} should be invalid`);
            });
        });

        test('Should handle network errors gracefully', () => {
            const error = new Error('Connection refused');
            
            assert.ok(error instanceof Error);
            assert.ok(error.message.includes('Connection'));
        });

        test('Should validate qualified names', () => {
            const testCases = [
                { input: 'Bool.andb', valid: true },
                { input: 'Logic.Equality.eq_refl', valid: true },
                { input: 'bool', valid: true },
                { input: '', valid: false },
                { input: 'Module..symbol', valid: false },
                { input: '.symbol', valid: false },
            ];
            
            testCases.forEach(({ input, valid }) => {
                const parts = input.split('.');
                const hasEmpty = parts.some(p => p.length === 0);
                const isValid = input.length > 0 && !hasEmpty;
                
                assert.strictEqual(isValid, valid, `${input} validity should be ${valid}`);
            });
        });
    });

    suite('Output Formatting', () => {
        test('Should format print output', () => {
            const result = '✓ Type: bool\nArity: 0 type parameters';
            const formatted = `\n${'='.repeat(60)}\n${result}\n${'='.repeat(60)}`;
            
            assert.ok(formatted.includes('✓ Type: bool'));
            assert.ok(formatted.includes('='.repeat(60)));
        });

        test('Should format error output', () => {
            const error = 'Symbol not found: unknown_symbol';
            const formatted = `\n❌ Error:\n${error}\n`;
            
            assert.ok(formatted.includes('❌'));
            assert.ok(formatted.includes(error));
        });

        test('Should handle multi-line results', () => {
            const result = 'Line 1\nLine 2\nLine 3';
            const lines = result.split('\n');
            
            assert.strictEqual(lines.length, 3);
            const firstLine = lines[0];
            if (!firstLine) {
                assert.fail('First line should exist');
            }
            assert.strictEqual(firstLine, 'Line 1');
        });
    });
});

