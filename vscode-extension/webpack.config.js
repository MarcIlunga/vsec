//@ts-check

'use strict';

const path = require('path');
const webpack = require('webpack');

/** @typedef {import('webpack').Configuration} WebpackConfig **/

/** @type WebpackConfig */
const extensionConfig = {
  target: 'node', // VSCode extensions run in a Node.js environment
  mode: 'none', // Leave source code as close as possible to original

  entry: {
    extension: './src/extension.ts',
    'tests/runTests': './tests/runTests.ts',
    'tests/suite/index': './tests/suite/index.ts',
    'tests/servers/mock-lsp': './tests/servers/mock-lsp.ts'
  },
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: '[name].js',
    libraryTarget: 'commonjs2',
  },
  externals: {
    vscode: 'commonjs vscode' // The vscode-module is created on-the-fly and must be excluded
  },
  resolve: {
    extensions: ['.ts', '.js']
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        exclude: /node_modules/,
        use: [
          {
            loader: 'ts-loader'
          }
        ]
      }
    ]
  },
  devtool: 'nosources-source-map',
  infrastructureLogging: {
    level: "log", // enables logging required for problem matchers
  },
  plugins: [
    new webpack.optimize.LimitChunkCountPlugin({
      maxChunks: 1 // Ensure only one output file per entry
    })
  ]
};

module.exports = [ extensionConfig ];