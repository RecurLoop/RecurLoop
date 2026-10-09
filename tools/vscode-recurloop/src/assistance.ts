import * as vscode from 'vscode';
import type { AnalysisResult, SymbolFact } from './analysis';
import { positionFromCodePoint } from './util';

export interface HelpFact {
  version: number; name: string; pattern: string; snippet: string;
  example: string; summary: string; tags: string;
}
export interface ArgumentFact {
  version: number; owner: string; name: string; docs: string;
  dictionary: string; kind: string; prototype: string;
}
export interface ExpectedFact {
  version: number; owner: string; start: number; name: string; matcher: string; literal: string; insertion: string;
}
export interface ValueFact {
  version: number; owner: string; argument: string; name: string; spelling: string;
}

export function helpMarkdown(contract: HelpFact, docs = ''): vscode.MarkdownString {
  const text = new vscode.MarkdownString();
  text.isTrusted = false;
  if (contract.summary || docs) text.appendMarkdown(contract.summary || docs);
  if (contract.example || contract.pattern)
    text.appendCodeblock(contract.example || `${contract.name} ${contract.pattern}`, 'recurloop');
  return text;
}

export function assistanceItems(document: vscode.TextDocument, result: AnalysisResult,
  kind: (name: string) => vscode.CompletionItemKind): vscode.CompletionItem[] {
  const items = new Map<string, vscode.CompletionItem>();
  const symbols = new Map(result.symbols.map(symbol => [symbol.name, symbol]));
  const end = document.positionAt(result.source.length);
  const addSymbol = (symbol: SymbolFact, spelling: string, start: number, expand = true): void => {
    const item = new vscode.CompletionItem(spelling, kind(symbol.kind));
    const contract = result.help.find(help => help.name === symbol.name && help.version === symbol.version);
    item.detail = symbol.signature || contract?.summary || symbol.kind;
    item.documentation = contract ? helpMarkdown(contract, symbol.docs) : new vscode.MarkdownString(symbol.docs);
    item.insertText = expand && contract?.snippet ? new vscode.SnippetString(contract.snippet.replaceAll('${phrase}', spelling)) : spelling;
    item.range = new vscode.Range(document.positionAt(start), end);
    item.sortText = spelling;
    items.set(`${spelling}:${start}`, item);
  };
  const inDictionary = (name: string, dictionary: string): boolean => {
    const prefix = dictionary ? `${dictionary}:` : '';
    return name.startsWith(prefix) && !name.slice(prefix.length).includes(':');
  };
  for (const expected of result.expected) {
    if (!expected.literal && !expected.matcher) continue;
    const start = result.mapping[Math.min(expected.start, result.mapping.length - 1)];
    const typed = result.source.slice(start);
    const range = new vscode.Range(positionFromCodePoint(document, result.mapping, expected.start), end);
    const argument = result.arguments.find(value => value.owner === expected.owner && value.version === expected.version && value.name === expected.name);
    if (expected.literal) {
      if (!expected.literal.startsWith(typed)) continue;
      const item = new vscode.CompletionItem(expected.literal, vscode.CompletionItemKind.Keyword);
      item.range = range;
      item.insertText = expected.insertion; item.sortText = expected.literal;
      item.detail = expected.owner;
      if (argument?.docs) item.documentation = new vscode.MarkdownString(argument.docs);
      items.set(`${expected.literal}:${start}`, item);
    } else if (argument?.dictionary || argument?.kind || argument?.prototype || result.values.some(value => value.owner === expected.owner && value.argument === expected.name)) {
      for (const value of result.values) {
        if (value.owner !== expected.owner || value.version !== expected.version || value.argument !== expected.name) continue;
        const symbol = symbols.get(value.name);
        if (!symbol) continue;
        const spelling = value.spelling;
        if (!spelling.startsWith(typed)) continue;
        addSymbol(symbol, spelling, start, false);
        if (argument?.docs) {
          const item = items.get(`${spelling}:${start}`)!;
          const docs = item.documentation as vscode.MarkdownString;
          docs.appendMarkdown(`\n\n${argument.docs}`);
        }
      }
    } else if (!typed && !['ignore', 'none', 'required', 'newline'].includes(expected.matcher)) {
      const item = new vscode.CompletionItem(`<${expected.name}:${expected.matcher}>`, vscode.CompletionItemKind.Snippet);
      item.range = range; item.detail = expected.owner;
      item.documentation = new vscode.MarkdownString(argument?.docs || '');
      item.insertText = expected.matcher === 'block'
        ? new vscode.SnippetString('{\n\t${1}\n}')
        : expected.matcher === 'string' ? new vscode.SnippetString('"${1}"')
        : new vscode.SnippetString().appendPlaceholder(expected.name);
      item.sortText = expected.name;
      items.set(`${expected.name}:${start}`, item);
    }
  }
  // At a phrase boundary, enumerate the real active dictionary, or the
  // explicitly qualified dictionary. No popularity or built-in keyword list.
  const finished = result.expected.find(expected => !expected.literal && !expected.matcher);
  const phraseBoundary = finished !== undefined && !result.expected.some(expected => expected.matcher);
  if (!result.expected.length || phraseBoundary) {
    const boundary = phraseBoundary && finished ? finished.start : result.completionStart;
    const start = boundary === undefined
      ? result.source.length - (result.source.match(/[^\s{}()[\],;"']*$/u)?.[0].length ?? 0)
      : result.mapping[Math.min(boundary, result.mapping.length - 1)];
    const typed = result.source.slice(start);
    const separator = Math.max(typed.lastIndexOf(':'), typed.lastIndexOf('.'));
    const dictionary = separator >= 0 ? typed.slice(0, separator).replaceAll('.', ':') : result.dictionary;
    const prefix = separator >= 0 ? typed.slice(separator + 1) : typed;
    for (const symbol of symbols.values()) {
      if (!inDictionary(symbol.name, dictionary)) continue;
      const leaf = dictionary ? symbol.name.slice(dictionary.length + 1) : symbol.name;
      if (!leaf || /[\x00-\x1f]/u.test(leaf) || !leaf.startsWith(prefix)) continue;
      addSymbol(symbol, leaf, start + separator + 1);
    }
  }
  return [...items.values()].sort((a, b) => String(a.sortText) < String(b.sortText) ? -1 : String(a.sortText) > String(b.sortText) ? 1 : 0);
}
