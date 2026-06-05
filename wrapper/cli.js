#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import http from 'http';
import { createRequire } from 'module';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const require = createRequire(import.meta.url);
const elmApp = require('./elm.cjs');

const command = process.argv[2];
const arg1 = process.argv[3];
const arg2 = process.argv[4];

if (!command) {
    console.log('Usage: yamoon compile <file.hyml>');
    console.log('       yamoon test <file.hyml>');
    console.log('       yamoon sync <file.hyml> <pier_path>');
    console.log('       yamoon --serve');
    process.exit(1);
}

const compileHyml = (filePath, isTest = false) => {
    const content = fs.readFileSync(filePath, 'utf8');
    const parsed = yaml.load(content);
    const json = JSON.stringify(parsed);
    const app = elmApp.Elm.Main.init();

    return new Promise((resolve, reject) => {
        if (isTest) {
            app.ports.requestTest.send(json);
        } else {
            app.ports.requestCompile.send(json);
        }

        app.ports.responseSuccess.subscribe((hoon) => resolve(hoon));
        app.ports.responseError.subscribe((err) => reject(err));
    });
};

if (command === 'compile' || command === 'test') {
    if (!arg1) {
        console.log(`Usage: yamoon ${command} <file.hyml>`);
        process.exit(1);
    }
    compileHyml(arg1, command === 'test')
        .then(hoon => console.log(hoon))
        .catch(err => {
            console.error('\x1b[31m%s\x1b[0m', `--- yamoon ${command === 'test' ? 'Testing' : 'Compilation'} Error ---`);
            console.error('\x1b[33m%s\x1b[0m', '  > ' + err);
            process.exit(1);
        });
} else if (command === 'sync') {
    if (!arg1 || !arg2) {
        console.log('Usage: yamoon sync <file.hyml> <pier_path>');
        process.exit(1);
    }
    
    const hymlPath = arg1;
    const pierPath = arg2;
    const fileName = path.basename(hymlPath, '.hyml');
    
    Promise.all([
        compileHyml(hymlPath, false),
        compileHyml(hymlPath, true).catch(() => null) // tests might be missing
    ]).then(([hoon, testHoon]) => {
        const deskPath = path.join(pierPath, 'base'); // default to base desk
        if (!fs.existsSync(deskPath)) {
            console.error(`Error: Could not find 'base' desk in pier at ${pierPath}`);
            process.exit(1);
        }

        const libPath = path.join(deskPath, 'lib', `${fileName}.hoon`);
        const testPath = path.join(deskPath, 'tests', 'lib', `${fileName}.hoon`);

        fs.mkdirSync(path.dirname(libPath), { recursive: true });
        fs.writeFileSync(libPath, hoon);
        console.log(`\x1b[32m✓\x1b[0m Synced library to ${libPath}`);

        if (testHoon) {
            fs.mkdirSync(path.dirname(testPath), { recursive: true });
            fs.writeFileSync(testPath, testHoon);
            console.log(`\x1b[32m✓\x1b[0m Synced test generator to ${testPath}`);
            console.log(`\nTo run tests in your Urbit pier:`);
            console.log(`  |mount %base`);
            console.log(`  -test /=base=/tests/lib/${fileName}`);
        }
    }).catch(err => {
        console.error('Sync failed:', err);
        process.exit(1);
    });

} else if (command === '--serve' || command === 'serve') {
    const port = process.env.PORT || 3000;
    const root = process.cwd();
    const editorPublic = path.join(__dirname, '../ide/public');

    const server = http.createServer((req, res) => {
        // Enable CORS
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

        if (req.method === 'OPTIONS') {
            res.writeHead(204);
            res.end();
            return;
        }

        const url = new URL(req.url, `http://${req.headers.host}`);

        // API Routes
        if (url.pathname === '/api/tree') {
            const getTree = (dir, relativeDir = '') => {
                try {
                    const files = fs.readdirSync(dir);
                    return files.map(file => {
                        const fullPath = path.join(dir, file);
                        const relPath = path.join(relativeDir, file);
                        const stats = fs.statSync(fullPath);
                        if (stats.isDirectory()) {
                            if (file === 'node_modules' || file === '.git' || file === 'elm-stuff' || file === '.elm-spa' || file === 'ide') return null;
                            return {
                                name: file,
                                path: relPath,
                                type: 'directory',
                                children: getTree(fullPath, relPath)
                            };
                        } else {
                            return {
                                name: file,
                                path: relPath,
                                type: 'file'
                            };
                        }
                    }).filter(Boolean);
                } catch (e) {
                    return [];
                }
            };
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(getTree(root)));
            return;
        }

        if (url.pathname === '/api/file') {
            const relPath = url.searchParams.get('path');
            if (!relPath) {
                res.writeHead(400);
                res.end('Missing path');
                return;
            }
            const fullPath = path.join(root, relPath);
            if (!fs.existsSync(fullPath)) {
                res.writeHead(404);
                res.end('Not found');
                return;
            }
            const content = fs.readFileSync(fullPath, 'utf8');
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end(content);
            return;
        }

        if (url.pathname === '/api/save' && req.method === 'POST') {
            let body = '';
            req.on('data', chunk => { body += chunk; });
            req.on('end', () => {
                try {
                    const { path: relPath, content } = JSON.parse(body);
                    const fullPath = path.join(root, relPath);
                    fs.writeFileSync(fullPath, content);
                    res.writeHead(200);
                    res.end('Saved');
                } catch (e) {
                    res.writeHead(500);
                    res.end(e.message);
                }
            });
            return;
        }

        if (url.pathname === '/api/compile' && req.method === 'POST') {
            let body = '';
            req.on('data', chunk => { body += chunk; });
            req.on('end', () => {
                try {
                    const { content } = JSON.parse(body);
                    const parsed = yaml.load(content);
                    const json = JSON.stringify(parsed);
                    const elm = elmApp.Elm.Main.init();
                    
                    elm.ports.requestCompile.send(json);
                    
                    const successSub = (hoon) => {
                        res.writeHead(200, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ success: true, hoon }));
                        cleanup();
                    };
                    const errorSub = (err) => {
                        res.writeHead(200, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ success: false, error: err }));
                        cleanup();
                    };
                    
                    const cleanup = () => {
                        elm.ports.responseSuccess.unsubscribe(successSub);
                        elm.ports.responseError.unsubscribe(errorSub);
                    };

                    elm.ports.responseSuccess.subscribe(successSub);
                    elm.ports.responseError.subscribe(errorSub);
                } catch (e) {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: false, error: 'YAML Error: ' + e.message }));
                }
            });
            return;
        }

        // Static File Serving
        let filePath = path.join(editorPublic, url.pathname);
        if (url.pathname === '/') filePath = path.join(editorPublic, 'index.html');

        if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
            const ext = path.extname(filePath);
            const contentTypes = {
                '.html': 'text/html',
                '.js': 'application/javascript',
                '.css': 'text/css',
                '.png': 'image/png',
                '.jpg': 'image/jpeg',
            };
            res.writeHead(200, { 'Content-Type': contentTypes[ext] || 'application/octet-stream' });
            res.end(fs.readFileSync(filePath));
        } else {
            // SPA Fallback: if not an API route and not a file, serve index.html
            if (url.pathname.startsWith('/api/')) {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'API route not found' }));
            } else {
                const indexHtml = path.join(editorPublic, 'index.html');
                if (fs.existsSync(indexHtml)) {
                    res.writeHead(200, { 'Content-Type': 'text/html' });
                    res.end(fs.readFileSync(indexHtml));
                } else {
                    res.writeHead(404);
                    res.end('Not found');
                }
            }
        }
    });

    server.listen(port, () => {
        console.log(`\x1b[32m%s\x1b[0m`, `Yamoon IDE is active!`);
        console.log(`  > Editor: http://localhost:${port}`);
        console.log(`  > Project: ${root}`);
        console.log(`\n(Press Ctrl+C to stop the server)`);
    });
}
