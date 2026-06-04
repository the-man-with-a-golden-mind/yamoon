# Yamoon Editor

Yamoon comes with a built-in web-based code editor to help you develop your projects more efficiently.

## Features

- **File Tree**: Browse your project files in the left sidebar.
- **Monaco Editor**: High-performance editor with syntax highlighting, code completion, and snippets.
- **Integrated Compilation**: Compile your Yamoon code directly in the browser and see the generated Hoon output or errors instantly.
- **Auto-Save**: Click the disk icon to save your changes back to the disk.
- **Modern UI**: Styled with Tailwind CSS for a sleek, dark-themed experience.

## Usage

To start the editor, run the following command in your project directory:

```bash
yamoon --serve
```

Then open your browser at [http://localhost:3000](http://localhost:3000).

## Development

If you want to modify the editor itself:

1.  Navigate to the `ide` directory.
2.  Install dependencies (if any, it's pure Elm).
3.  Build the frontend:
```bash
npm run ide:build
```
4.  Restart the `yamoon --serve` command.

### Manual Build Command
```bash
cd ide
npx elm make src/Main.elm --output=public/elm.js --optimize
```
