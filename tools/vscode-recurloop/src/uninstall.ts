import * as path from 'path';
import { removeManagedRuntimes } from './runtimeOwnership';

try {
  removeManagedRuntimes(path.join(__dirname, 'managed-runtimes.json'));
} catch (error) {
  console.error('Cannot remove extension-managed RecurLoop runtimes:', error);
  process.exitCode = 1;
}
