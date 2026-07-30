import path from 'node:path';

const truthyValues = new Set(['1', 'true', 'yes', 'on']);

export function parseConfig(argv = process.argv.slice(2), env = process.env) {
  const config = {
    databasePath: env.COUNTDOWN_TODO_DATABASE?.trim() || null,
    readOnly: truthyValues.has(
      (env.COUNTDOWN_TODO_MCP_READ_ONLY ?? '').trim().toLowerCase(),
    ),
    checkOnly: false,
    showHelp: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--database') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error('--database 需要一个 SQLite 数据库路径');
      }
      config.databasePath = value;
      index += 1;
    } else if (argument.startsWith('--database=')) {
      config.databasePath = argument.slice('--database='.length);
    } else if (argument === '--read-only') {
      config.readOnly = true;
    } else if (argument === '--check') {
      config.checkOnly = true;
    } else if (argument === '--help' || argument === '-h') {
      config.showHelp = true;
    } else {
      throw new Error(`未知参数: ${argument}`);
    }
  }

  if (config.databasePath) {
    config.databasePath = path.resolve(config.databasePath);
  }
  return config;
}

export const helpText = `CountdownTodo MCP Server

用法:
  npm start -- --database /absolute/path/uni_sync_<username>.db

选项:
  --database <path>  CountdownTodo SQLite 数据库的绝对路径
  --read-only        仅注册只读 MCP 工具
  --check            检查数据库和表结构后退出
  --help             显示帮助

环境变量:
  COUNTDOWN_TODO_DATABASE       数据库路径（可替代 --database）
  COUNTDOWN_TODO_MCP_READ_ONLY  设为 1/true/yes/on 时启用只读模式`;
