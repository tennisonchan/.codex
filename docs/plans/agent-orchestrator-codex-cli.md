# Agent Orchestrator Design - Codex CLI Approach
**Created by:** Claude
**Date:** 2025-11-18
**Status:** Design Phase
**Approach:** Codex CLI Process Execution

## At a Glance
- Goal: run tasks in isolated `claude-code` processes with per-task workspaces for stronger isolation and richer tool access.
- Emphasis: workspace prep, process supervision, output parsing, timeout handling.
- Decisions: standardize workspace template, define resource limits, and choose result schema.
- Next step: prototype supervisor that spawns a single Codex CLI worker from queue input.

## Executive Summary

This design uses **Codex CLI processes** instead of direct Anthropic API calls. Each task spawns an isolated `claude-code` process with its own workspace, providing strong isolation and access to full Claude Code capabilities.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              Event Queue (from Webhook Gateway)          │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│         Agent Orchestrator (Process Manager)             │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Task Queue & Concurrency Manager               │   │
│  └───────────┬─────────────────────────────────────┘   │
│              ▼                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Workspace Manager                              │   │
│  │  - Create isolated workspace per task           │   │
│  │  - Prepare context files                        │   │
│  │  - Clone repo if needed                         │   │
│  └───────────┬─────────────────────────────────────┘   │
│              ▼                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Codex CLI Process Manager                      │   │
│  │  - Spawn claude-code processes                  │   │
│  │  - Monitor stdout/stderr                        │   │
│  │  - Handle timeouts                              │   │
│  │  - Capture output artifacts                     │   │
│  └───────────┬─────────────────────────────────────┘   │
│              ▼                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Output Parser & Result Processor               │   │
│  │  - Parse JSON/markdown output                   │   │
│  │  - Extract actions taken                        │   │
│  │  - Identify errors/failures                     │   │
│  └─────────────────────────────────────────────────┘   │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  External Actions (Linear API, Slack API, GitHub API)   │
│  (Codex CLI handles these via MCP servers)              │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Workspace Manager

**Purpose:** Create isolated file system workspaces for each Codex CLI execution.

**Workspace Structure:**
```
/tmp/codex-tasks/
├── task-{uuid}/
│   ├── workspace/                 # Working directory for Codex
│   │   ├── .claude/              # Task-specific config
│   │   │   ├── config.toml       # MCP servers, settings
│   │   │   └── auth.json         # API credentials
│   │   └── repo/                 # Git repo (if needed)
│   ├── context/                  # Input context files
│   │   ├── issue.json            # Linear issue data
│   │   ├── related.json          # Related issues
│   │   └── team.json             # Team configuration
│   ├── prompts/                  # Prompt templates
│   │   └── triage.md             # Task-specific prompt
│   ├── outputs/                  # Codex outputs
│   │   ├── result.json           # Structured result
│   │   ├── log.txt               # Execution log
│   │   └── artifacts/            # Screenshots, files created
│   └── metadata.json             # Task metadata
```

**Lifecycle:**
```typescript
class WorkspaceManager {
  async createWorkspace(task: AgentTask): Promise<Workspace> {
    const workspaceId = `task-${task.id}`;
    const basePath = `/tmp/codex-tasks/${workspaceId}`;

    // 1. Create directory structure
    await fs.mkdir(`${basePath}/workspace/.claude`, { recursive: true });
    await fs.mkdir(`${basePath}/context`);
    await fs.mkdir(`${basePath}/prompts`);
    await fs.mkdir(`${basePath}/outputs/artifacts`, { recursive: true });

    // 2. Copy .claude configuration
    await this.setupClaudeConfig(basePath);

    // 3. Write context files
    await this.writeContextFiles(basePath, task);

    // 4. Generate prompt
    await this.writePrompt(basePath, task);

    // 5. Clone repo if needed (for code-related tasks)
    if (task.requiresCodebase) {
      await this.cloneRepo(basePath, task.repo);
    }

    return {
      id: workspaceId,
      basePath,
      workingDir: `${basePath}/workspace`,
      contextDir: `${basePath}/context`,
      outputDir: `${basePath}/outputs`
    };
  }

  async setupClaudeConfig(basePath: string): Promise<void> {
    // Copy MCP server configuration
    const config = {
      mcpServers: {
        linear: {
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-linear"],
          env: {
            LINEAR_API_KEY: process.env.LINEAR_API_KEY
          }
        },
        slack: {
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-slack"],
          env: {
            SLACK_BOT_TOKEN: process.env.SLACK_BOT_TOKEN
          }
        },
        github: {
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-github"],
          env: {
            GITHUB_TOKEN: process.env.GITHUB_TOKEN
          }
        }
      }
    };

    await fs.writeFile(
      `${basePath}/workspace/.claude/config.toml`,
      toml.stringify(config)
    );
  }

  async cleanup(workspace: Workspace): Promise<void> {
    // Archive important artifacts before deletion
    await this.archiveArtifacts(workspace);

    // Delete workspace (or keep for debugging)
    if (!process.env.DEBUG_KEEP_WORKSPACES) {
      await fs.rm(workspace.basePath, { recursive: true });
    }
  }
}
```

### 2. Codex CLI Process Manager

**Purpose:** Spawn and monitor Codex CLI processes.

**Process Execution:**
```typescript
class CodexProcessManager {
  private activeProcesses = new Map<string, ChildProcess>();

  async executeTask(
    workspace: Workspace,
    task: AgentTask
  ): Promise<ExecutionResult> {

    const promptFile = `${workspace.basePath}/prompts/triage.md`;
    const outputFile = `${workspace.outputDir}/result.json`;
    const logFile = `${workspace.outputDir}/log.txt`;

    // Build Codex CLI command
    const args = [
      '--workspace', workspace.workingDir,
      '--prompt-file', promptFile,
      '--non-interactive',
      '--json-output', outputFile
    ];

    // Spawn process
    const process = spawn('claude-code', args, {
      cwd: workspace.workingDir,
      env: {
        ...process.env,
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
        // Pass context file locations via env vars
        CONTEXT_DIR: workspace.contextDir,
        OUTPUT_DIR: workspace.outputDir
      },
      stdio: ['ignore', 'pipe', 'pipe']
    });

    this.activeProcesses.set(task.id, process);

    // Monitor output
    const stdout: string[] = [];
    const stderr: string[] = [];

    process.stdout.on('data', (data) => {
      const line = data.toString();
      stdout.push(line);
      this.emit('process:stdout', task.id, line);
    });

    process.stderr.on('data', (data) => {
      const line = data.toString();
      stderr.push(line);
      this.emit('process:stderr', task.id, line);
    });

    // Set timeout
    const timeout = setTimeout(() => {
      this.killProcess(task.id, 'timeout');
    }, task.timeout || 600000); // 10 min default

    // Wait for completion
    const exitCode = await new Promise<number>((resolve) => {
      process.on('exit', (code) => {
        clearTimeout(timeout);
        this.activeProcesses.delete(task.id);
        resolve(code || 0);
      });
    });

    // Save logs
    await fs.writeFile(logFile, stdout.join('\n'));

    // Parse results
    if (exitCode === 0 && await fs.exists(outputFile)) {
      const result = JSON.parse(await fs.readFile(outputFile, 'utf-8'));
      return {
        success: true,
        result,
        logs: stdout.join('\n'),
        artifacts: await this.collectArtifacts(workspace)
      };
    } else {
      return {
        success: false,
        error: {
          exitCode,
          stdout: stdout.join('\n'),
          stderr: stderr.join('\n')
        }
      };
    }
  }

  killProcess(taskId: string, reason: string): void {
    const process = this.activeProcesses.get(taskId);
    if (process) {
      process.kill('SIGTERM');
      this.emit('process:killed', taskId, reason);
    }
  }

  async collectArtifacts(workspace: Workspace): Promise<Artifact[]> {
    const artifactsDir = `${workspace.outputDir}/artifacts`;
    const files = await fs.readdir(artifactsDir);

    return Promise.all(
      files.map(async (file) => ({
        filename: file,
        path: `${artifactsDir}/${file}`,
        size: (await fs.stat(`${artifactsDir}/${file}`)).size,
        type: this.detectFileType(file)
      }))
    );
  }
}
```

### 3. Prompt Builder

**Purpose:** Generate task-specific prompts that leverage Codex CLI features.

**Prompt Templates:**
```typescript
class PromptBuilder {
  buildLinearTriagePrompt(task: AgentTask, context: LinearContext): string {
    return `# Linear Issue Triage Task

You are triaging Linear issue ${context.issue.identifier}.

## Context Files Available

The following JSON files contain all the context you need:
- ${process.env.CONTEXT_DIR}/issue.json - Full issue details
- ${process.env.CONTEXT_DIR}/related.json - Related issues
- ${process.env.CONTEXT_DIR}/team.json - Team configuration (labels, priorities, states)

## Your Task

1. **Read the context files** using the Read tool
2. **Analyze the issue** to determine:
   - Issue type: bug, feature, enhancement, tech-debt
   - Severity: P0 (critical), P1 (high), P2 (medium), P3 (low)
   - Affected component: frontend, backend, api, infra
   - Complexity estimate: 1-5

3. **Update the issue** using Linear MCP tools:
   - Use \`mcp__linear__update_issue\` to add labels and set priority
   - Use \`mcp__linear__create_comment\` to post your triage analysis

4. **Write structured output** to ${process.env.OUTPUT_DIR}/result.json:
\`\`\`json
{
  "issueId": "${context.issue.id}",
  "actions": [
    {
      "type": "labels_added",
      "labels": ["bug", "backend"],
      "reasoning": "..."
    },
    {
      "type": "priority_set",
      "priority": 1,
      "reasoning": "..."
    },
    {
      "type": "comment_posted",
      "commentId": "...",
      "summary": "..."
    }
  ],
  "analysis": {
    "type": "bug",
    "severity": "P1",
    "component": "backend",
    "complexity": 3,
    "reasoning": "..."
  }
}
\`\`\`

## Guidelines

- Be thorough but concise in your analysis
- Focus on actionable insights
- If information is missing, note it in your comment
- Use the team's existing labels (check team.json)
- Consider similar past issues (check related.json)

## Important

- Use MCP tools to update Linear directly
- Write the result.json file with structured output
- Do not create any other files in the workspace
`;
  }

  buildSlackBugAnalysisPrompt(task: AgentTask, context: SlackContext): string {
    return `# Slack Bug Analysis Task

You are analyzing a potential bug report from Slack channel ${context.channel.name}.

## Context Files Available

- ${process.env.CONTEXT_DIR}/message.json - Original message
- ${process.env.CONTEXT_DIR}/thread.json - Thread replies
- ${process.env.CONTEXT_DIR}/channel.json - Channel info

## Your Task

1. **Read the context** to understand the bug report
2. **Determine if valid bug:**
   - Are steps to reproduce clear?
   - Is expected vs actual behavior described?
   - Is this a bug or user error?

3. **If information missing:**
   - Use \`mcp__slack__post_message\` to ask clarifying questions in thread
   - Be specific about what's needed

4. **If valid bug:**
   - Use \`mcp__linear__create_issue\` to create a Linear issue
   - Include all relevant details from Slack
   - Set appropriate labels and priority
   - Use \`mcp__slack__post_message\` to reply with Linear issue link

5. **If not a bug:**
   - Use \`mcp__slack__post_message\` to explain politely
   - Suggest alternative solutions if applicable

6. **Write output** to ${process.env.OUTPUT_DIR}/result.json

## Output Format

\`\`\`json
{
  "isValidBug": true,
  "actions": [
    {
      "type": "linear_issue_created",
      "issueId": "PROJ-123",
      "issueUrl": "https://linear.app/..."
    },
    {
      "type": "slack_message_posted",
      "messageTs": "...",
      "text": "..."
    }
  ],
  "analysis": {
    "bugType": "...",
    "severity": "...",
    "reasoning": "..."
  }
}
\`\`\`
`;
  }

  buildGitHubReviewPrompt(task: AgentTask, context: GitHubContext): string {
    return `# GitHub Pull Request Review Task

You are reviewing PR #${context.pr.number} in ${context.pr.repo}.

## Context Files Available

- ${process.env.CONTEXT_DIR}/pr.json - PR metadata
- ${process.env.CONTEXT_DIR}/diff.json - Full diff
- ${process.env.CONTEXT_DIR}/files.json - Changed files list

## Codebase Access

The repository is cloned at: ${process.env.WORKSPACE_DIR}/repo
- You can use Read tool to examine files
- You can use Grep/Glob to search code
- Branch: ${context.pr.branch}

## Your Task

1. **Analyze code changes** for:
   - Bugs and logic errors
   - Security vulnerabilities (XSS, SQL injection, auth issues)
   - Code quality and best practices
   - Performance concerns
   - Missing tests or documentation

2. **For each issue found:**
   - Use \`mcp__github__post_review_comment\` with file path and line number
   - Explain the issue clearly
   - Suggest a fix
   - Indicate severity: blocking, important, or nit

3. **Post summary review:**
   - Overall assessment
   - Count of issues by severity
   - Positive feedback on good changes
   - DO NOT approve or request changes (human will decide)

4. **Write output** to ${process.env.OUTPUT_DIR}/result.json

## Output Format

\`\`\`json
{
  "reviewComplete": true,
  "actions": [
    {
      "type": "inline_comment",
      "file": "src/api/users.ts",
      "line": 42,
      "commentId": "...",
      "severity": "blocking",
      "issue": "SQL injection vulnerability"
    },
    {
      "type": "summary_comment",
      "commentId": "...",
      "issuesFound": 5
    }
  ],
  "summary": {
    "blocking": 1,
    "important": 2,
    "nits": 2,
    "overallAssessment": "..."
  }
}
\`\`\`
`;
  }
}
```

### 4. Output Parser

**Purpose:** Parse Codex CLI output and extract structured results.

**Implementation:**
```typescript
class OutputParser {
  async parseResult(workspace: Workspace): Promise<ExecutionResult> {
    const resultFile = `${workspace.outputDir}/result.json`;
    const logFile = `${workspace.outputDir}/log.txt`;

    // Check if result.json exists
    if (!await fs.exists(resultFile)) {
      return {
        success: false,
        error: {
          type: 'no_output',
          message: 'Codex did not write result.json',
          logs: await this.readLogs(logFile)
        }
      };
    }

    // Parse JSON result
    const result = JSON.parse(await fs.readFile(resultFile, 'utf-8'));

    // Validate structure
    if (!this.validateResult(result)) {
      return {
        success: false,
        error: {
          type: 'invalid_output',
          message: 'Result does not match expected schema',
          result
        }
      };
    }

    // Extract actions taken
    const actions = this.extractActions(result);

    // Collect artifacts
    const artifacts = await this.collectArtifacts(workspace);

    // Read logs
    const logs = await this.readLogs(logFile);

    return {
      success: true,
      result,
      actions,
      artifacts,
      logs,
      metrics: {
        duration: this.calculateDuration(logs),
        toolCalls: this.countToolCalls(logs)
      }
    };
  }

  validateResult(result: any): boolean {
    // Validate against expected schema
    return (
      typeof result === 'object' &&
      Array.isArray(result.actions) &&
      result.actions.every(action =>
        typeof action.type === 'string'
      )
    );
  }

  extractActions(result: any): Action[] {
    return result.actions.map(action => ({
      type: action.type,
      timestamp: new Date(),
      details: action,
      platform: this.detectPlatform(action.type)
    }));
  }

  async readLogs(logFile: string): Promise<string> {
    if (await fs.exists(logFile)) {
      return await fs.readFile(logFile, 'utf-8');
    }
    return '';
  }

  countToolCalls(logs: string): number {
    // Parse logs to count MCP tool calls
    const toolCallPattern = /mcp__\w+__\w+/g;
    const matches = logs.match(toolCallPattern);
    return matches ? matches.length : 0;
  }
}
```

## Codex CLI Invocation Patterns

### Pattern 1: Simple Prompt (No Repo)

**Use Case:** Linear triage, Slack bug analysis

```bash
claude-code \
  --workspace /tmp/task-123/workspace \
  --prompt-file /tmp/task-123/prompts/triage.md \
  --non-interactive \
  --json-output /tmp/task-123/outputs/result.json
```

**Environment Variables:**
```bash
CONTEXT_DIR=/tmp/task-123/context
OUTPUT_DIR=/tmp/task-123/outputs
ANTHROPIC_API_KEY=sk-ant-...
```

### Pattern 2: With Repository (Code Review)

**Use Case:** GitHub PR review, code-related tasks

```bash
# First clone repo
git clone https://github.com/org/repo.git /tmp/task-123/workspace/repo
cd /tmp/task-123/workspace/repo
git checkout pr-branch

# Then run Codex
claude-code \
  --workspace /tmp/task-123/workspace/repo \
  --prompt-file /tmp/task-123/prompts/review.md \
  --non-interactive \
  --json-output /tmp/task-123/outputs/result.json
```

### Pattern 3: With Git Worktree (PR Creation)

**Use Case:** Creating PRs for Linear tickets

```bash
# Create worktree for isolated branch
cd /shared/repo
git worktree add /tmp/task-123/workspace/worktree feature/PROJ-123

# Run Codex in worktree
claude-code \
  --workspace /tmp/task-123/workspace/worktree \
  --prompt-file /tmp/task-123/prompts/implement.md \
  --non-interactive \
  --json-output /tmp/task-123/outputs/result.json

# Cleanup worktree after
git worktree remove /tmp/task-123/workspace/worktree
```

## Complete Agent Orchestrator

```typescript
import { spawn, ChildProcess } from 'child_process';
import { EventEmitter } from 'events';
import fs from 'fs/promises';

interface AgentTask {
  id: string;
  type: TaskType;
  priority: number;
  context: {
    source: 'linear' | 'slack' | 'github';
    resourceId: string;
    metadata: Record<string, any>;
  };
  requiresCodebase?: boolean;
  repo?: {
    url: string;
    branch?: string;
  };
  timeout?: number;
}

type TaskType =
  | 'linear_triage'
  | 'slack_bug_analysis'
  | 'github_pr_review'
  | 'pr_creation';

export class AgentOrchestrator extends EventEmitter {
  private workspaceManager: WorkspaceManager;
  private processManager: CodexProcessManager;
  private promptBuilder: PromptBuilder;
  private outputParser: OutputParser;
  private contextGatherer: ContextGatherer;

  private activeProcesses = new Map<string, Workspace>();
  private maxConcurrent = 3;

  constructor() {
    super();
    this.workspaceManager = new WorkspaceManager();
    this.processManager = new CodexProcessManager();
    this.promptBuilder = new PromptBuilder();
    this.outputParser = new OutputParser();
    this.contextGatherer = new ContextGatherer();
  }

  async executeTask(task: AgentTask): Promise<ExecutionResult> {
    // Wait for capacity
    await this.waitForCapacity();

    let workspace: Workspace | null = null;

    try {
      this.emit('task:started', task);

      // 1. Gather context from external APIs
      const context = await this.contextGatherer.gather(task);

      // 2. Create workspace
      workspace = await this.workspaceManager.createWorkspace(task);
      this.activeProcesses.set(task.id, workspace);

      // 3. Write context files
      await this.workspaceManager.writeContextFiles(workspace, context);

      // 4. Generate prompt
      const prompt = this.promptBuilder.buildPrompt(task, context);
      await fs.writeFile(
        `${workspace.basePath}/prompts/${task.type}.md`,
        prompt
      );

      // 5. Clone repo if needed
      if (task.requiresCodebase && task.repo) {
        await this.cloneRepository(workspace, task.repo);
      }

      // 6. Execute Codex CLI
      const result = await this.processManager.executeTask(workspace, task);

      // 7. Parse output
      const parsedResult = await this.outputParser.parseResult(workspace);

      // 8. Emit completion
      this.emit('task:completed', task, parsedResult);

      return parsedResult;

    } catch (error) {
      this.emit('task:failed', task, error);
      throw error;

    } finally {
      // Cleanup workspace
      if (workspace) {
        this.activeProcesses.delete(task.id);
        await this.workspaceManager.cleanup(workspace);
      }
    }
  }

  async cloneRepository(
    workspace: Workspace,
    repo: { url: string; branch?: string }
  ): Promise<void> {
    const repoPath = `${workspace.workingDir}/repo`;

    await new Promise((resolve, reject) => {
      const clone = spawn('git', [
        'clone',
        '--depth', '1',
        '--single-branch',
        ...(repo.branch ? ['--branch', repo.branch] : []),
        repo.url,
        repoPath
      ]);

      clone.on('exit', (code) => {
        code === 0 ? resolve(null) : reject(new Error(`Git clone failed: ${code}`));
      });
    });
  }

  async waitForCapacity(): Promise<void> {
    while (this.activeProcesses.size >= this.maxConcurrent) {
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }

  getStatus() {
    return {
      activeProcesses: this.activeProcesses.size,
      capacity: this.maxConcurrent,
      processes: Array.from(this.activeProcesses.entries()).map(([id, workspace]) => ({
        taskId: id,
        workspace: workspace.id
      }))
    };
  }
}
```

## Configuration for Codex CLI

**Environment Variables:**
```bash
# API Keys (passed to Codex CLI)
ANTHROPIC_API_KEY=sk-ant-...
LINEAR_API_KEY=lin_api_...
SLACK_BOT_TOKEN=xoxb-...
GITHUB_TOKEN=ghp_...

# Orchestrator Settings
CODEX_CLI_PATH=/usr/local/bin/claude-code
WORKSPACE_BASE_PATH=/tmp/codex-tasks
MAX_CONCURRENT_PROCESSES=3
DEFAULT_TIMEOUT_MS=600000

# Workspace Cleanup
DEBUG_KEEP_WORKSPACES=false
ARCHIVE_ARTIFACTS_TO_S3=true
S3_ARTIFACT_BUCKET=codex-artifacts
```

**MCP Server Configuration Template:**
```toml
# /tmp/codex-tasks/task-{id}/workspace/.claude/config.toml

[mcpServers.linear]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-linear"]
env = { LINEAR_API_KEY = "${LINEAR_API_KEY}" }

[mcpServers.slack]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-slack"]
env = { SLACK_BOT_TOKEN = "${SLACK_BOT_TOKEN}" }

[mcpServers.github]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "${GITHUB_TOKEN}" }
```

## Advantages of Codex CLI Approach

### 1. **Strong Isolation**
- Each task runs in separate process
- Filesystem isolation per workspace
- No shared state between tasks
- Easy to kill/restart

### 2. **Full Claude Code Features**
- Access to all CLI tools (Read, Edit, Write, Grep, Glob, Bash)
- Can leverage hooks
- Can use existing .claude configuration
- Screenshot capture capabilities

### 3. **Debugging**
- Can replay tasks by re-running CLI command
- Full logs captured in workspace
- Can inspect workspace after failure
- Easy to test prompts manually

### 4. **Flexibility**
- Can run different Codex versions per task
- Can test new features before production
- Can pass custom flags per task type
- Environment isolation

## Disadvantages & Mitigations

### 1. **Higher Resource Usage**

**Problem:** Each process needs memory/CPU

**Mitigation:**
- Limit concurrency (3-5 processes max)
- Use containerization for resource limits
- Implement aggressive cleanup
- Monitor resource usage and auto-scale

### 2. **Slower Startup**

**Problem:** Process spawn + MCP server init takes ~5-10 seconds

**Mitigation:**
- Accept the latency for better isolation
- Optimize workspace creation (parallel steps)
- Pre-warm MCP servers if possible
- Use faster storage (SSD)

### 3. **Output Parsing Complexity**

**Problem:** Need to parse CLI output instead of structured API responses

**Mitigation:**
- Require structured output file (result.json)
- Validate output schema strictly
- Provide clear output format in prompts
- Have fallback parsing for unstructured output

### 4. **Error Handling**

**Problem:** Process crashes, timeouts, non-zero exits

**Mitigation:**
```typescript
// Comprehensive error handling
try {
  const result = await executeTask(task);
} catch (error) {
  if (error.code === 'ETIMEDOUT') {
    // Process timeout
    await killProcess(task.id);
    await archiveLogs(workspace);
    await notifyTimeout(task);
  } else if (error.code === 'ENOENT') {
    // Codex CLI not found
    throw new Error('claude-code binary not in PATH');
  } else if (error.exitCode !== 0) {
    // Non-zero exit
    const logs = await readLogs(workspace);
    await analyzeFailure(logs, error);
  }
}
```

## Deployment Considerations

### Containerized Deployment

**Dockerfile:**
```dockerfile
FROM node:20-slim

# Install Codex CLI
RUN npm install -g claude-code

# Install Git for repo cloning
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Create workspace directory
RUN mkdir -p /tmp/codex-tasks && chmod 777 /tmp/codex-tasks

# Copy orchestrator code
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .

# Run orchestrator
CMD ["node", "dist/orchestrator.js"]
```

### Resource Limits

**Docker Compose:**
```yaml
services:
  orchestrator:
    build: .
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
    volumes:
      - /tmp/codex-tasks:/tmp/codex-tasks
    environment:
      - MAX_CONCURRENT_PROCESSES=3
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

## Cost Comparison: CLI vs API

**Codex CLI (Process-based):**
```
Infrastructure:
- Higher CPU usage: ~20% more
- Higher memory: ~2GB per process
- Storage: ~100MB per workspace

API Costs:
- Same as direct API (Anthropic charges same)
- ~$0.05 per task average

Total: Slightly higher infra cost, same API cost
```

**When to Use CLI:**
- Need strong isolation
- Complex tasks requiring full Claude Code features
- Want to leverage existing .claude config
- Debugging is important
- Acceptable latency (~10s startup)

**When to Use Direct API:**
- High volume (>500 tasks/hour)
- Need sub-second response times
- Simple tasks (single API call)
- Cost optimization critical
- Limited resources

## Recommended Hybrid Approach

```typescript
class HybridOrchestrator {
  async executeTask(task: AgentTask): Promise<ExecutionResult> {
    // Use CLI for complex tasks
    if (this.shouldUseCliExecution(task)) {
      return await this.cliOrchestrator.executeTask(task);
    }

    // Use direct API for simple tasks
    return await this.apiOrchestrator.executeTask(task);
  }

  shouldUseCliExecution(task: AgentTask): boolean {
    return (
      task.requiresCodebase ||           // Need file access
      task.type === 'pr_creation' ||     // Need git operations
      task.type === 'github_pr_review' || // Need code analysis
      task.complexity === 'high'         // Multi-step workflows
    );
  }
}
```

## Next Steps

1. **Build Workspace Manager** - Implement workspace creation and cleanup
2. **Build Process Manager** - Implement Codex CLI spawning and monitoring
3. **Create Prompt Templates** - Write task-specific prompts
4. **Build Output Parser** - Parse result.json and logs
5. **Integration Testing** - Test with real Linear/Slack/GitHub tasks
6. **Deployment** - Containerize and deploy to staging

Would you like me to start implementing the Workspace Manager or any other component?
