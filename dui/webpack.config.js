const path = require('path');
const webpack = require('webpack');
const HtmlWebpackPlugin = require('html-webpack-plugin');

// Builds the DUI React app into ../html as a single bundle so the FiveM
// resource ships ready-to-run. Output: ../html/index.html + ../html/app.bundle.js
module.exports = {
    entry: path.resolve(__dirname, 'src/index.jsx'),
    output: {
        path: path.resolve(__dirname, '..', 'html'),
        filename: 'app.bundle.js',
        clean: false,
    },
    // Keep everything in one file — FiveM `files{}` lists each asset, so a
    // single bundle is simplest. The default `react-player` import (not
    // `/lazy`) already pulls every backend into the main chunk.
    optimization: {
        splitChunks: false,
        runtimeChunk: false,
    },
    resolve: {
        extensions: ['.js', '.jsx'],
    },
    module: {
        rules: [
            {
                test: /\.jsx?$/,
                exclude: /node_modules/,
                use: 'babel-loader',
            },
            {
                test: /\.css$/,
                use: ['style-loader', 'css-loader'],
            },
        ],
    },
    plugins: [
        new HtmlWebpackPlugin({
            template: path.resolve(__dirname, 'src/index.html'),
            filename: 'index.html',
            inject: 'body',
        }),
        // react-player lazy-loads each backend via dynamic import(), which
        // would emit a dozen extra chunk files. Collapse everything into the
        // single app.bundle.js so there are no runtime chunk fetches — much
        // simpler to ship as FiveM `files{}`.
        new webpack.optimize.LimitChunkCountPlugin({ maxChunks: 1 }),
    ],
};
