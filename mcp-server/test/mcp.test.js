import assert from 'node:assert/strict';
import { rmSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

import { createTestDatabase } from './support.js';

const projectDirectory = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);

test('serves CountdownTodo tools over MCP stdio', async () => {
  const fixture = createTestDatabase();
  const cleanEnvironment = Object.fromEntries(
    Object.entries(process.env).filter(([, value]) => value != null),
  );
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(projectDirectory, 'src/index.js')],
    env: {
      ...cleanEnvironment,
      COUNTDOWN_TODO_DATABASE: fixture.databasePath,
    },
    stderr: 'pipe',
  });
  const client = new Client({ name: 'countdown-todo-test', version: '1.0.0' });

  try {
    await client.connect(transport);
    const tools = await client.listTools();
    assert.equal(tools.tools.some((tool) => tool.name === 'list_todos'), true);
    assert.equal(tools.tools.some((tool) => tool.name === 'create_todo'), true);

    const statusResult = await client.callTool({
      name: 'mcp_status',
      arguments: {},
    });
    assert.equal(statusResult.structuredContent.schemaValid, true);

    const createResult = await client.callTool({
      name: 'create_todo',
      arguments: {
        title: '由 MCP 创建',
        timeMode: 'unscheduled',
      },
    });
    assert.equal(createResult.isError, undefined, JSON.stringify(createResult));
    assert.equal(createResult.structuredContent.todo.title, '由 MCP 创建');
    assert.match(createResult.content[0].text, /由 MCP 创建/);

    const listResult = await client.callTool({
      name: 'list_todos',
      arguments: { query: 'MCP' },
    });
    assert.equal(listResult.structuredContent.count, 1);
    assert.match(listResult.content[0].text, /由 MCP 创建/);
  } finally {
    await client.close();
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test('read-only MCP mode does not advertise mutation tools', async () => {
  const fixture = createTestDatabase();
  const cleanEnvironment = Object.fromEntries(
    Object.entries(process.env).filter(([, value]) => value != null),
  );
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(projectDirectory, 'src/index.js')],
    env: {
      ...cleanEnvironment,
      COUNTDOWN_TODO_DATABASE: fixture.databasePath,
      COUNTDOWN_TODO_MCP_READ_ONLY: '1',
    },
    stderr: 'pipe',
  });
  const client = new Client(
    {
      name: 'countdown-todo-read-only-test',
      version: '1.0.0',
    },
    { versionNegotiation: { mode: { pin: '2026-07-28' } } },
  );

  try {
    await client.connect(transport);
    assert.equal(client.getProtocolEra(), 'modern');
    const tools = await client.listTools();
    assert.equal(tools.tools.some((tool) => tool.name === 'list_todos'), true);
    assert.equal(tools.tools.some((tool) => tool.name === 'create_todo'), false);
    assert.equal(tools.tools.some((tool) => tool.name === 'delete_todo'), false);
  } finally {
    await client.close();
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});
