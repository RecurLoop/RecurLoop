# Publishing RecurLoop for VS Code

## 1. Pick the Marketplace publisher ID

The extension currently contains:

```json
"publisher": "recurloop"
```

A VS Code extension ID is `<publisher>.<name>`, so with the current manifest it
will be `recurloop.recurloop-vscode`. The Marketplace publisher ID must actually
belong to you. If `recurloop` is unavailable, create another publisher and edit
`publisher` in `package.json` before the first publication.

Do not casually change the extension `name` after publishing. Marketplace names
are identifiers, not just display labels.

## 2. Build and inspect the VSIX locally

```bash
cd tools/vscode-recurloop
npm install
npm run check
npm run package
```

This produces `recurloop-vscode-0.1.0.vsix`.

Install exactly that artifact before publishing:

```bash
code --install-extension recurloop-vscode-0.1.0.vsix --force
```

## 3. Create a Visual Studio Marketplace publisher

Sign in to the Visual Studio Marketplace publisher management page and create a
publisher. Its ID must equal the `publisher` value in `package.json`.

For a one-off/manual publication in 2026, `vsce` still supports an Azure DevOps
Personal Access Token with `Marketplace -> Manage` scope and `All accessible
organizations`, followed by:

```bash
npx vsce login <publisher-id>
```

Microsoft has announced retirement of global Azure DevOps PATs on
**December 1, 2026**. For automated/long-lived publishing, use Microsoft Entra
ID / workload identity federation rather than building CI around a long-lived
PAT.

## 4. Publish

After changing `publisher` if necessary:

```bash
cd tools/vscode-recurloop
npm run check
npx vsce publish
```

For the next releases, increment SemVer first, for example:

```bash
npx vsce publish patch
```

or set the exact version:

```bash
npx vsce publish 0.2.0
```

## 5. Useful pre-release flow

```bash
npx vsce package --pre-release
npx vsce publish --pre-release
```

Use a normal `major.minor.patch` version; VS Code Marketplace pre-release is a
publication flag, not an npm-style `-beta` suffix.
