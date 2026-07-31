#!/usr/bin/env node

import { serveStdio } from '@modelcontextprotocol/server/stdio';

import { parseConfig, helpText } from './config.js';
import { CountdownTodoDatabase } from './database.js';
import { createMcpServer } from './server.js';

try {
  const config = parseConfig();
  if (config.showHelp) {
    process.stdout.write(`${helpText}\n`);
    process.exit(0);
  }

  const repository = new CountdownTodoDatabase(config.databasePath, {
    readOnly: config.readOnly,
  });

  if (config.checkOnly) {
    process.stdout.write(
      `${JSON.stringify(repository.validateSchema(), null, 2)}\n`,
    );
    repository.close();
    process.exit(0);
  }

  console.error(
    `CountdownTodo MCP 已启动 (${config.readOnly ? '只读' : '可读写'})`,
  );
  const handle = serveStdio(() => createMcpServer(repository), {
    onerror: (error) => console.error(error.message),
  });

  let closing = false;
  const close = async () => {
    if (closing) return;
    closing = true;
    try {
      await handle.close();
    } finally {
      repository.close();
    }
  };
  process.once('SIGINT', () => void close());
  process.once('SIGTERM', () => void close());
  process.once('exit', () => {
    try {
      repository.close();
    } catch {
      // The MCP transport may already have closed the repository.
    }
  });
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
