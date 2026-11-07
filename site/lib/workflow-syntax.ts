import { StreamLanguage } from '@codemirror/language';
import { shell } from '@codemirror/legacy-modes/mode/shell';
import { sqlite } from '@codemirror/legacy-modes/mode/sql';
import { dockerFile } from '@codemirror/legacy-modes/mode/dockerfile';
import { http } from '@codemirror/legacy-modes/mode/http';
import { diff } from '@codemirror/legacy-modes/mode/diff';
import { yaml } from '@codemirror/legacy-modes/mode/yaml';

export function workflowLanguage(filePath: string): 'shell' | 'sql' | 'dockerfile' | 'http' | 'diff' | 'yaml' | undefined {
  const name = filePath.split('/').at(-1)?.toLowerCase() ?? '';
  if (name === 'dockerfile' || name.startsWith('dockerfile.') || name.endsWith('.dockerfile')) return 'dockerfile';
  if (name === '.env' || name.startsWith('.env.') || /\.(?:sh|bash|zsh)$/.test(name)) return 'shell';
  if (name.endsWith('.sql')) return 'sql';
  if (/\.(?:http|rest)$/.test(name)) return 'http';
  if (/\.(?:diff|patch)$/.test(name)) return 'diff';
  if (/\.(?:yml|yaml)$/.test(name)) return 'yaml';
}
const parsers = { shell, sql: sqlite, dockerfile: dockerFile, http, diff, yaml };
export function workflowLanguageSupport(filePath: string) {
  const language = workflowLanguage(filePath);
  return language ? [StreamLanguage.define(parsers[language])] : [];
}
