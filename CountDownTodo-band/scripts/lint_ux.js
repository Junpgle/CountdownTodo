'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const projectRoot = path.resolve(__dirname, '..')
const sourceRoot = path.join(projectRoot, 'src')
const eslintBin = path.join(projectRoot, 'node_modules', 'eslint', 'bin', 'eslint.js')

function collectUxFiles(directory) {
  const files = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name)
    if (entry.isDirectory()) {
      files.push(...collectUxFiles(entryPath))
    } else if (entry.isFile() && entry.name.endsWith('.ux')) {
      files.push(entryPath)
    }
  }
  return files
}

function extractScripts(source) {
  const scripts = []
  const scriptPattern = /<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi
  let match
  while ((match = scriptPattern.exec(source)) !== null) {
    scripts.push(match[1])
  }
  return scripts.join('\n\n')
}

const temporaryRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), 'countdown-todo-band-ux-lint-'),
)

try {
  const temporaryFiles = []
  for (const sourceFile of collectUxFiles(sourceRoot)) {
    const relativePath = path.relative(sourceRoot, sourceFile)
    const temporaryFile = path.join(
      temporaryRoot,
      relativePath.replace(/\.ux$/, '.js'),
    )
    fs.mkdirSync(path.dirname(temporaryFile), { recursive: true })
    fs.writeFileSync(
      temporaryFile,
      extractScripts(fs.readFileSync(sourceFile, 'utf8')),
    )
    temporaryFiles.push(temporaryFile)
  }

  if (temporaryFiles.length > 0) {
    const result = spawnSync(
      process.execPath,
      [
        eslintBin,
        '--format',
        'stylish',
        '--parser-options',
        '{"ecmaVersion":2020,"sourceType":"module"}',
        ...temporaryFiles,
      ],
      { cwd: projectRoot, stdio: 'inherit' },
    )
    process.exitCode = result.status === null ? 1 : result.status
  }
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true })
}
