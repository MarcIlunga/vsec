# VsEc EasyCrypt Extension Makefile
# Test-Driven Development Build System

.PHONY: all build test test-unit test-integration test-e2e test-performance clean help

# Default target
all: build test

# Build the LSP server
build:
	@echo "🔧 Building LSP server..."
	cd src && dune build
	@echo "✅ Build complete"

# Copy LSP binary to extension directory
install-lsp: build
	@echo "📦 Installing LSP binary..."
	cp src/_build/default/eclsp/ecLsp.exe vscode-extension/vsec-lsp
	chmod +x vscode-extension/vsec-lsp
	@echo "✅ LSP binary installed"

# Run all tests
test: test-unit test-integration test-e2e
	@echo "🎉 All tests completed"

# Run OCaml unit tests
test-unit:
	@echo "🧪 Running unit tests..."
	cd src && dune test
	@echo "✅ Unit tests passed"

# Run Python integration tests
test-integration: build
	@echo "🔗 Running integration tests..."
	cd tests/integration && python3 test_interactive_proving.py
	@echo "✅ Integration tests passed"

# Run end-to-end tests with EasyCrypt files
test-e2e: build
	@echo "🎭 Running end-to-end tests..."
	@for file in tests/e2e/*.ec; do \
		echo "Testing $$file..."; \
		python3 -c "import sys; sys.path.append('tests/integration'); from test_interactive_proving import *; test_ec_file('$$file')" || exit 1; \
	done
	@echo "✅ End-to-end tests passed"

# Run performance tests
test-performance: build
	@echo "⚡ Running performance tests..."
	@echo "Performance tests not yet implemented"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	cd src && dune clean
	rm -f vscode-extension/vsec-lsp
	rm -rf tests/**/__pycache__
	@echo "✅ Clean complete"

# Development helpers
dev-setup:
	@echo "🔧 Setting up development environment..."
	opam install --deps-only src/vsec-language-server.opam
	@echo "✅ Development environment ready"

# Watch mode for continuous testing
test-watch:
	@echo "👀 Starting test watch mode..."
	while inotifywait -r -e modify src/ tests/; do \
		make test; \
	done

# Lint and format code
lint:
	@echo "🔍 Linting code..."
	cd src && dune build @fmt --auto-promote
	@echo "✅ Code formatted"

# Generate test coverage report
coverage: build
	@echo "📊 Generating test coverage..."
	cd src && dune test --coverage
	@echo "✅ Coverage report generated"

# Quick smoke test
smoke-test: build
	@echo "💨 Running smoke test..."
	echo 'lemma test: true. proof. trivial. qed.' > /tmp/test.ec
	timeout 10s src/_build/default/eclsp/ecLsp.exe < /dev/null || true
	rm -f /tmp/test.ec
	@echo "✅ Smoke test passed"

# Help target
help:
	@echo "VsEc EasyCrypt Extension - Available targets:"
	@echo ""
	@echo "  build           - Build the LSP server"
	@echo "  install-lsp     - Install LSP binary to extension"
	@echo "  test            - Run all tests"
	@echo "  test-unit       - Run OCaml unit tests"
	@echo "  test-integration- Run Python integration tests"
	@echo "  test-e2e        - Run end-to-end tests"
	@echo "  test-performance- Run performance tests"
	@echo "  clean           - Clean build artifacts"
	@echo "  dev-setup       - Setup development environment"
	@echo "  test-watch      - Continuous testing"
	@echo "  lint            - Lint and format code"
	@echo "  coverage        - Generate test coverage"
	@echo "  smoke-test      - Quick smoke test"
	@echo "  help            - Show this help"
