import { McpServer } from '@modelcontextprotocol/server';
import * as z from 'zod/v4';

const readAnnotations = Object.freeze({
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
});

const writeAnnotations = Object.freeze({
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false,
});

const recurrenceSchema = z.enum([
  'none',
  'daily',
  'customDays',
  'weekly',
  'monthly',
  'yearly',
  'weekdays',
]);

const timeModeSchema = z.enum(['unscheduled', 'dateOnly', 'deadline']);

export function createMcpServer(repository) {
  const server = new McpServer({
    name: 'countdown-todo',
    version: '0.1.0',
  });

  server.registerTool(
    'mcp_status',
    {
      title: 'CountdownTodo MCP 状态',
      description: '检查 CountdownTodo 数据库连接、模式和 MCP 能力。',
      inputSchema: z.object({}),
      annotations: readAnnotations,
    },
    async () => asResult(repository.validateSchema(), 'CountdownTodo MCP 已连接'),
  );

  server.registerTool(
    'list_todo_groups',
    {
      title: '列出待办分类',
      description: '列出可用于 groupId 的 CountdownTodo 个人待办分类。',
      inputSchema: z.object({}),
      annotations: readAnnotations,
    },
    async () => {
      const groups = repository.listTodoGroups();
      return asResult({ groups, count: groups.length }, `找到 ${groups.length} 个分类`);
    },
  );

  server.registerTool(
    'list_todos',
    {
      title: '查询待办',
      description:
        '查询 CountdownTodo 个人待办。默认仅返回未完成项，可按关键词、分类和截止范围筛选。',
      inputSchema: z.object({
        status: z.enum(['pending', 'completed', 'all']).default('pending'),
        query: z.string().trim().min(1).optional(),
        groupId: z.string().uuid().optional(),
        dueFrom: z.string().optional().describe('ISO 8601 日期或时间，下界'),
        dueBefore: z.string().optional().describe('ISO 8601 日期或时间，上界'),
        limit: z.number().int().min(1).max(200).default(50),
      }),
      annotations: readAnnotations,
    },
    async (input) => {
      try {
        const todos = repository.listTodos(input);
        return asResult({ todos, count: todos.length }, `找到 ${todos.length} 条待办`);
      } catch (error) {
        return asError(error);
      }
    },
  );

  server.registerTool(
    'get_todo',
    {
      title: '读取待办详情',
      description: '通过真实 todoId 读取一条 CountdownTodo 个人待办。',
      inputSchema: z.object({ todoId: z.string().uuid() }),
      annotations: readAnnotations,
    },
    async ({ todoId }) => {
      const todo = repository.getTodo(todoId);
      return todo
        ? asResult({ todo }, `已读取待办「${todo.title}」`)
        : asError(new Error(`找不到待办: ${todoId}`));
    },
  );

  if (!repository.readOnly) {
    registerWriteTools(server, repository);
  }
  return server;
}

function registerWriteTools(server, repository) {
  server.registerTool(
    'create_todo',
    {
      title: '创建待办',
      description:
        '创建个人待办并加入 CountdownTodo 同步队列。未安排、日期待办和明确截止时间必须通过 timeMode 区分。',
      inputSchema: z.object({
        title: z.string().trim().min(1).max(500),
        remark: z.string().max(10000).nullable().optional(),
        timeMode: timeModeSchema.default('unscheduled'),
        dueDate: z
          .string()
          .nullable()
          .optional()
          .describe('dateOnly 使用 YYYY-MM-DD；deadline 使用 ISO 8601 时间'),
        groupId: z.string().uuid().nullable().optional(),
        reminderMinutes: z.number().int().min(0).max(43200).nullable().optional(),
        recurrence: recurrenceSchema.default('none'),
        customIntervalDays: z.number().int().min(1).max(3650).nullable().optional(),
        recurrenceEndDate: z.string().nullable().optional(),
      }),
      annotations: writeAnnotations,
    },
    async (input) => callWrite(() => repository.createTodo(input), '已创建待办'),
  );

  server.registerTool(
    'update_todo',
    {
      title: '修改待办',
      description:
        '修改一条个人待办并加入同步队列。修改时间时必须同时传 timeMode；null 可清空备注、分类或提醒。',
      inputSchema: z.object({
        todoId: z.string().uuid(),
        title: z.string().trim().min(1).max(500).optional(),
        remark: z.string().max(10000).nullable().optional(),
        groupId: z.string().uuid().nullable().optional(),
        reminderMinutes: z.number().int().min(0).max(43200).nullable().optional(),
        timeMode: timeModeSchema.optional(),
        dueDate: z.string().nullable().optional(),
      }),
      annotations: writeAnnotations,
    },
    async ({ todoId, ...changes }) =>
      callWrite(() => repository.updateTodo(todoId, changes), '已修改待办'),
  );

  server.registerTool(
    'set_todo_completion',
    {
      title: '设置待办完成状态',
      description:
        '完成或恢复一条个人待办。循环待办仅作用于传入 todoId 对应的真实期次。',
      inputSchema: z.object({
        todoId: z.string().uuid(),
        completed: z.boolean().default(true),
      }),
      annotations: { ...writeAnnotations, idempotentHint: true },
    },
    async ({ todoId, completed }) =>
      callWrite(
        () => repository.setTodoCompletion(todoId, completed),
        completed ? '已完成待办' : '已恢复待办',
      ),
  );

  server.registerTool(
    'delete_todo',
    {
      title: '删除待办',
      description: '将一条个人待办软删除到回收站，并加入同步队列。',
      inputSchema: z.object({ todoId: z.string().uuid() }),
      annotations: {
        ...writeAnnotations,
        destructiveHint: true,
        idempotentHint: true,
      },
    },
    async ({ todoId }) =>
      callWrite(() => repository.deleteTodo(todoId), '待办已移入回收站'),
  );
}

async function callWrite(action, message) {
  try {
    const todo = action();
    return asResult({ todo }, `${message}「${todo.title}」`);
  } catch (error) {
    return asError(error);
  }
}

function asResult(structuredContent, text) {
  const serialized = JSON.stringify(structuredContent, null, 2);
  return {
    content: [{ type: 'text', text: `${text}\n${serialized}` }],
    structuredContent,
  };
}

function asError(error) {
  return {
    content: [
      {
        type: 'text',
        text: error instanceof Error ? error.message : String(error),
      },
    ],
    isError: true,
  };
}
