# Agent Orchestrator Design Plan
**Created by:** Claude
**Date:** 2025-11-18
**Status:** Design Phase

## At a Glance
- Goal: orchestrate Claude agent instances for webhook-triggered tasks (triage, PR review, Slack analysis).
- Focus: dynamic spawning, context gathering, concurrency limits, auditability, retries.
- Decision points: lifecycle manager vs external queue ownership; failure handling + retry policy.
- Outcome needed: approved architecture to begin implementation and integration with webhook gateway.

## Executive Summary

The Agent Orchestrator is the core component that manages Claude AI agent instances to handle webhook-triggered automation tasks. It acts as a "manager" that spawns agents, prepares context, monitors execution, and processes results for tasks like Linear triage, Slack bug analysis, and GitHub PR reviews.

## Problem Statement

We need a system that can:
1. Dynamically spawn AI agents in response to webhook events
2. Prepare rich context from multiple data sources (Linear, Slack, GitHub, codebase)
3. Manage concurrent agent execution with resource limits
4. Handle multi-turn agent conversations with tool use
5. Track agent actions and maintain audit trails
6. Gracefully handle failures and implement retry logic

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              Event Queue (from Webhook Gateway)          │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│            Agent Orchestrator (This Component)           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Task Queue & Concurrency Manager               │   │
│  └───────────┬─────────────────────────────────────┘   │
│              ▼                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Context Gatherer (MCP Integration)             │   │
│  └───────────┬─────────────────────────────────────┘   │
│              ▼                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Agent Lifecycle Manager                        │   │
│  │  - Spawn agent instances                        │   │
│  │  - Execute conversation loops                   │   │
│  │  - Handle tool calls                            │   │
│  │  - Monitor health & timeout                     │   │
│  └───────────┬─────────────────────────────────────┘   │
│              ▼                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Result Processor & Action Tracker              │   │
│  └─────────────────────────────────────────────────┘   │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  External Actions (Linear API, Slack API, GitHub API)   │
└─────────────────────────────────────────────────────────┘
```

## Implementation Approaches

### Approach 1: Direct Anthropic API (Simplest)
**Description:** Make direct API calls to Anthropic with custom tool handling.

**Pros:**
- Simple implementation
- Stateless and easy to scale horizontally
- Full control over request/response cycle
- Lower infrastructure overhead

**Cons:**
- Manual tool execution loop implementation
- Limited to single-turn or manually-managed multi-turn
- More code to maintain
- Need to implement conversation state management

**Use Case:** Best for simple, single-purpose tasks with minimal tool use.

### Approach 2: Claude Agent SDK (Recommended)
**Description:** Use the official Claude Agent SDK with MCP server integration.

**Pros:**
- Built-in multi-turn conversation handling
- Native MCP server support
- Automatic tool execution loop
- Better error handling and retries
- Official support and updates

**Cons:**
- Requires Node.js runtime
- Less granular control over execution
- Dependency on SDK updates
- Slightly higher overhead

**Use Case:** Best for complex tasks requiring multiple tool calls and decision-making.

### Approach 3: Subprocess Management (Most Flexible)
**Description:** Spawn actual `claude-code` CLI processes for each task.

**Pros:**
- Access to full Claude Code CLI capabilities
- Isolated execution environments
- Can use existing .claude configuration
- True workspace isolation

**Cons:**
- Heavy resource usage (process per task)
- Harder to manage programmatically
- Output parsing complexity
- Slower startup time

**Use Case:** Best when you need full CLI features and workspace isolation.

**Recommendation:** Start with Approach 2 (Claude Agent SDK) for the MVP, with option to migrate to Approach 3 for specific use cases requiring workspace isolation.

## Core Components

### 1. AgentOrchestrator Class

**Responsibilities:**
- Task queue management
- Concurrency control (max N parallel agents)
- Agent lifecycle management
- Event emission for monitoring
- Health checks and metrics

**Key Configuration:**
```typescript
{
  maxConcurrent: 3,           // Max parallel agents
  maxToolCalls: 50,           // Safety limit per task
  timeout: 600000,            // 10 min per task
  retryAttempts: 2,           // Retry failed tasks
  model: 'claude-sonnet-4-5-20250929'
}
```

**Public API:**
```typescript
interface IAgentOrchestrator {
  executeTask(task: AgentTask): Promise<ExecutionResult>;
  getStatus(): OrchestratorStatus;
  cancelTask(taskId: string): Promise<void>;
  on(event: string, handler: Function): void;
}
```

### 2. Context Gatherer

**Purpose:** Fetch relevant data before agent execution to provide rich context.

**Data Sources:**
- **Linear:** Issue details, related issues, team info, labels, states
- **Slack:** Message content, thread history, channel context, user info
- **GitHub:** PR details, diff, commits, checks, reviews, files changed
- **Codebase:** Recent changes, related files, test results
- **Sentry:** Error logs, stack traces, occurrence patterns

**Implementation:**
```typescript
class ContextGatherer {
  async gatherForLinearTriage(issueId: string): Promise<LinearContext> {
    const [issue, related, team, labels] = await Promise.all([
      this.linearClient.getIssue(issueId),
      this.linearClient.findRelatedIssues(issueId),
      this.linearClient.getTeamInfo(),
      this.linearClient.getAvailableLabels()
    ]);

    return { issue, related, team, labels };
  }

  async gatherForSlackBugAnalysis(messageTs: string): Promise<SlackContext> {
    // Similar pattern for Slack data
  }

  async gatherForGitHubReview(prNumber: number): Promise<GitHubContext> {
    // Similar pattern for GitHub data
  }
}
```

**Optimization Strategy:**
- Cache frequently accessed data (team info, labels, user lists)
- Parallel fetches with Promise.all
- Incremental context gathering (fetch more only if needed)
- Configurable context depth per task type

### 3. Agent Lifecycle Manager

**Purpose:** Manage individual agent instances through their execution lifecycle.

**Lifecycle States:**
```
QUEUED → PREPARING_CONTEXT → SPAWNING → ACTIVE → COMPLETING → COMPLETED
                                      ↓
                                  FAILED/TIMEOUT
```

**Agent Instance Tracking:**
```typescript
interface AgentInstance {
  taskId: string;
  status: AgentStatus;
  startedAt: Date;
  lastActivityAt: Date;
  messages: Message[];          // Conversation history
  toolCalls: number;            // Safety counter
  actions: Action[];            // Actions taken
  metadata: Record<string, any>;
}
```

**Health Monitoring:**
- Track last activity timestamp
- Enforce timeout limits
- Monitor tool call count
- Detect stuck agents
- Resource usage tracking (future)

### 4. Conversation Loop Handler

**Purpose:** Execute multi-turn conversations with Claude, handling tool calls iteratively.

**Flow:**
```typescript
1. Send initial prompt with system instructions
2. Receive response from Claude
3. If stop_reason === 'tool_use':
   a. Extract tool calls from response
   b. Execute each tool (sequentially or parallel)
   c. Collect tool results
   d. Add assistant message + tool results to conversation
   e. Continue to step 2
4. If stop_reason === 'end_turn':
   a. Extract final response
   b. Return execution result
5. If max_turns or timeout reached:
   a. Force stop and return partial result
```

**Safety Mechanisms:**
- Max tool calls limit (prevent infinite loops)
- Timeout enforcement
- Token usage tracking
- Rate limit handling with exponential backoff

### 5. Tool Execution Router

**Purpose:** Route tool calls from Claude to appropriate API handlers.

**Tool Categories:**

**Linear Tools:**
```typescript
- update_linear_issue(issueId, updates)
- create_linear_comment(issueId, body)
- add_linear_labels(issueId, labels[])
- set_linear_priority(issueId, priority)
- assign_linear_issue(issueId, userId)
- search_linear_issues(query, filters)
```

**Slack Tools:**
```typescript
- post_slack_message(channel, text, threadTs?)
- react_to_message(channel, timestamp, emoji)
- update_slack_message(channel, timestamp, text)
- get_thread_context(channel, threadTs)
```

**GitHub Tools:**
```typescript
- post_review_comment(repo, prNumber, body, path?, line?)
- create_pull_request(repo, title, body, branch)
- update_pr_status(repo, prNumber, state)
- request_changes(repo, prNumber, comments[])
- fetch_pr_files(repo, prNumber)
```

**Codebase Tools:**
```typescript
- search_code(query, filePattern?)
- read_file(path, lineStart?, lineEnd?)
- git_blame(path, line)
- run_tests(pattern?)
- get_recent_changes(since?)
```

**Tool Execution Strategy:**
- Validate inputs before execution
- Execute with proper error handling
- Return structured responses
- Log all actions for audit
- Implement retries for transient failures

### 6. Result Processor

**Purpose:** Parse agent results and update task state.

**Result Structure:**
```typescript
interface ExecutionResult {
  success: boolean;
  summary: string;              // Human-readable summary
  actions: Action[];            // All actions taken
  artifacts?: {                 // Optional outputs
    createdIssueId?: string;
    prUrl?: string;
    slackMessageTs?: string;
  };
  metrics: {
    duration: number;           // Execution time (ms)
    toolCalls: number;          // Total tool calls
    tokensUsed: number;         // API tokens used
    cost: number;               // Estimated cost
  };
  error?: {
    type: string;
    message: string;
    stack?: string;
  };
}
```

**Post-Processing Actions:**
1. Store result in database
2. Emit completion event
3. Update webhook source (e.g., Linear comment)
4. Send notifications (Slack updates)
5. Trigger follow-up tasks if needed
6. Update metrics/analytics

## Task Type Specifications

### Linear Triage Task

**Trigger:** `issue.created` or `issue.updated` webhook

**Context Required:**
- Issue details (title, description, current state, labels, priority)
- Related issues (similar titles, same component)
- Team configuration (available labels, priorities, states)
- Recent similar issues for pattern detection

**Agent Goals:**
1. Analyze issue description for severity and type
2. Determine appropriate labels (bug, feature, enhancement)
3. Set priority (P0-P3) based on impact
4. Suggest affected component/area
5. Add structured triage comment
6. Optionally assign to team member

**Success Criteria:**
- Issue updated with 1+ relevant labels
- Priority set appropriately
- Triage comment posted with reasoning

**Prompt Template:**
```typescript
const triagePrompt = (context: LinearContext) => `
You are triaging Linear issue ${context.issue.identifier}.

**Issue Details:**
Title: ${context.issue.title}
Description: ${context.issue.description}
Current State: ${context.issue.state.name}
Created: ${context.issue.createdAt}

**Your Tasks:**
1. Analyze the issue and determine:
   - Type: bug, feature, enhancement, tech-debt
   - Severity: P0 (critical), P1 (high), P2 (medium), P3 (low)
   - Affected component (frontend, backend, api, infra, etc.)
   - Complexity estimate (1-5)

2. Update the issue:
   - Add appropriate labels using update_linear_issue tool
   - Set priority using set_linear_priority tool
   - Add a comment with your analysis using create_linear_comment tool

3. In your comment, include:
   - Issue type and severity with reasoning
   - Affected component
   - Complexity estimate
   - Suggested next steps
   - Any questions or missing information

Available labels: ${context.labels.map(l => l.name).join(', ')}

Be concise but thorough. Focus on actionable insights.
`;
```

### Slack Bug Analysis Task

**Trigger:** Message posted in #bugs channel or keywords detected

**Context Required:**
- Message content and thread replies
- Channel context (#bugs, #support, etc.)
- User info (reporter, team member?)
- Similar past reports
- Related Linear issues

**Agent Goals:**
1. Extract bug details (steps to reproduce, expected/actual behavior)
2. Ask clarifying questions if information missing
3. Determine if valid bug or user error
4. Create Linear issue if valid
5. Respond in Slack thread with analysis

**Success Criteria:**
- Linear issue created if valid bug
- Slack response posted with findings
- User acknowledged or questions asked

**Prompt Template:**
```typescript
const slackBugPrompt = (context: SlackContext) => `
You are analyzing a potential bug report from Slack.

**Message:**
Channel: ${context.channel.name}
User: ${context.user.name}
Content: ${context.message.text}

**Thread Context:**
${context.thread.map(m => `${m.user}: ${m.text}`).join('\n')}

**Your Tasks:**
1. Analyze if this is a valid bug report:
   - Are steps to reproduce provided?
   - Is expected vs actual behavior clear?
   - Is this a bug or user misunderstanding?

2. If information is missing:
   - Use post_slack_message to ask clarifying questions in thread
   - Be specific about what's needed

3. If it's a valid bug:
   - Create a Linear issue using create_linear_from_slack tool
   - Include all relevant details
   - Set appropriate labels and priority
   - Post in Slack thread with Linear issue link

4. If it's not a bug:
   - Explain why politely in Slack thread
   - Suggest alternative solutions if applicable

Be helpful and professional. Err on the side of creating an issue if uncertain.
`;
```

### GitHub PR Review Task

**Trigger:** `pull_request.opened` or `pull_request.synchronize` webhook

**Context Required:**
- PR metadata (title, description, author)
- Files changed and diff
- CI check results
- Related Linear issue
- Previous review comments

**Agent Goals:**
1. Analyze code changes for issues
2. Check for common bugs, security issues, best practices
3. Post inline comments on specific lines
4. Provide summary review comment
5. Do not approve/reject (human decision)

**Success Criteria:**
- Review comments posted (if issues found)
- Summary comment with findings
- Constructive, actionable feedback

**Prompt Template:**
```typescript
const prReviewPrompt = (context: GitHubContext) => `
You are reviewing GitHub PR #${context.pr.number}.

**PR Details:**
Title: ${context.pr.title}
Author: ${context.pr.author}
Description: ${context.pr.description}

**Files Changed (${context.files.length}):**
${context.files.map(f => `- ${f.filename} (+${f.additions}, -${f.deletions})`).join('\n')}

**Your Tasks:**
1. Review code changes for:
   - Bugs and logic errors
   - Security vulnerabilities (XSS, SQL injection, auth issues)
   - Code quality and best practices
   - Performance concerns
   - Missing tests or documentation

2. Use fetch_pr_files to read specific files if needed

3. For each issue found:
   - Use post_review_comment with file path and line number
   - Explain the issue clearly
   - Suggest a fix
   - Indicate severity (blocking, important, nit)

4. Post summary review using post_review_comment:
   - Overall assessment
   - Count of issues by severity
   - Positive feedback on good changes
   - Do NOT approve or request changes (human will decide)

Focus on meaningful issues, not style nitpicks.
`;
```

## Data Models

### Task Schema
```typescript
interface AgentTask {
  id: string;                    // Unique task ID
  source: 'linear' | 'slack' | 'github';
  type: TaskType;
  priority: number;              // 0 (highest) to 3 (lowest)
  status: TaskStatus;
  context: {
    resourceId: string;          // Issue ID, message TS, PR number
    eventType: string;           // Webhook event type
    metadata: Record<string, any>;
  };
  createdAt: Date;
  startedAt?: Date;
  completedAt?: Date;
  result?: ExecutionResult;
  retryCount: number;
  maxRetries: number;
}

type TaskType =
  | 'linear_triage'
  | 'linear_comment_response'
  | 'slack_bug_analysis'
  | 'slack_question_answer'
  | 'github_pr_review'
  | 'github_issue_triage'
  | 'pr_creation';

type TaskStatus =
  | 'queued'
  | 'preparing'
  | 'active'
  | 'completed'
  | 'failed'
  | 'timeout'
  | 'cancelled';
```

### Action Schema
```typescript
interface Action {
  id: string;
  taskId: string;
  type: ActionType;
  platform: 'linear' | 'slack' | 'github' | 'codebase';
  timestamp: Date;
  details: {
    operation: string;           // 'update', 'create', 'comment', etc.
    resourceId: string;          // ID of resource acted upon
    changes: Record<string, any>; // What changed
    success: boolean;
    error?: string;
  };
}

type ActionType =
  | 'issue_updated'
  | 'comment_created'
  | 'label_added'
  | 'priority_set'
  | 'message_posted'
  | 'pr_created'
  | 'review_posted';
```

## Configuration Management

### Environment Variables
```bash
# API Keys
ANTHROPIC_API_KEY=sk-ant-...
LINEAR_API_KEY=lin_api_...
SLACK_BOT_TOKEN=xoxb-...
GITHUB_TOKEN=ghp_...
SENTRY_DSN=https://...

# Orchestrator Config
AGENT_MAX_CONCURRENT=3
AGENT_TIMEOUT_MS=600000
AGENT_MAX_TOOL_CALLS=50
AGENT_MODEL=claude-sonnet-4-5-20250929

# Database
DATABASE_URL=postgresql://...
REDIS_URL=redis://...

# Observability
LOG_LEVEL=info
METRICS_ENABLED=true
SENTRY_ENVIRONMENT=production
```

### MCP Server Configuration
```json
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-linear"],
      "env": {
        "LINEAR_API_KEY": "${LINEAR_API_KEY}"
      }
    },
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "${SLACK_BOT_TOKEN}"
      }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

## Error Handling Strategy

### Error Categories

1. **Transient Errors** (Retry)
   - API rate limits (429)
   - Network timeouts
   - Temporary service unavailability (503)
   - Deadlock or lock timeout

2. **User Errors** (Don't Retry)
   - Invalid resource ID (404)
   - Insufficient permissions (403)
   - Malformed request (400)
   - Resource conflict (409)

3. **System Errors** (Alert + Investigate)
   - MCP server crash
   - Database connection loss
   - Out of memory
   - Unexpected exceptions

### Retry Logic
```typescript
class RetryPolicy {
  maxAttempts = 3;
  baseDelay = 1000;          // 1 second
  maxDelay = 30000;          // 30 seconds
  backoffMultiplier = 2;

  async executeWithRetry<T>(
    fn: () => Promise<T>,
    errorCategory: (error: Error) => 'transient' | 'user' | 'system'
  ): Promise<T> {
    let lastError: Error;

    for (let attempt = 1; attempt <= this.maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;
        const category = errorCategory(error);

        if (category !== 'transient' || attempt === this.maxAttempts) {
          throw error;
        }

        const delay = Math.min(
          this.baseDelay * Math.pow(this.backoffMultiplier, attempt - 1),
          this.maxDelay
        );

        await this.sleep(delay);
      }
    }

    throw lastError;
  }
}
```

### Failure Modes & Recovery

**Scenario: Agent Timeout**
- Action: Cancel agent execution
- Log: Full conversation history + context
- Notify: Slack alert to #dev-alerts
- Recovery: Manual intervention or retry with increased timeout

**Scenario: Tool Execution Failure**
- Action: Return error to agent, allow retry with different approach
- Log: Tool name, input, error details
- Notify: If repeated failures, alert team
- Recovery: Agent can try alternative tools or ask for help

**Scenario: MCP Server Crash**
- Action: Attempt restart, queue tasks
- Log: Crash dump, recent requests
- Notify: Immediate alert (critical)
- Recovery: Restart MCP server, replay queued tasks

**Scenario: Rate Limit Exceeded**
- Action: Pause task execution
- Log: Current rate limit status
- Notify: Warning (if sustained)
- Recovery: Exponential backoff, resume when limit resets

## Monitoring & Observability

### Key Metrics

**Performance Metrics:**
```typescript
- agent.execution.duration (histogram)
- agent.execution.tool_calls (histogram)
- agent.execution.tokens_used (counter)
- agent.execution.cost (gauge)
- agent.concurrent_count (gauge)
- agent.queue_depth (gauge)
```

**Success Metrics:**
```typescript
- agent.execution.success_rate (gauge)
- agent.execution.failure_rate (gauge)
- agent.execution.timeout_rate (gauge)
- agent.retry_count (counter)
```

**Business Metrics:**
```typescript
- tasks.completed.by_type (counter)
- actions.taken.by_platform (counter)
- issues.triaged.count (counter)
- prs.reviewed.count (counter)
- bugs.analyzed.count (counter)
```

### Logging Strategy

**Structured Logging Format:**
```typescript
{
  timestamp: '2025-11-18T10:30:00Z',
  level: 'info',
  service: 'agent-orchestrator',
  taskId: 'task-123',
  agentId: 'agent-456',
  event: 'task.completed',
  details: {
    taskType: 'linear_triage',
    duration: 45000,
    toolCalls: 5,
    actionsCount: 3,
    success: true
  },
  metadata: {
    resourceId: 'PROJ-123',
    source: 'linear'
  }
}
```

**Log Levels:**
- **DEBUG:** Tool inputs/outputs, conversation turns
- **INFO:** Task lifecycle events, successful completions
- **WARN:** Retries, rate limits, degraded performance
- **ERROR:** Failures, exceptions, timeouts

### Alerting Rules

**Critical Alerts (PagerDuty):**
- Agent success rate < 80% over 15 minutes
- MCP server down for > 1 minute
- Database connection lost
- Queue depth > 100 tasks

**Warning Alerts (Slack):**
- Agent success rate < 90% over 1 hour
- Average execution time > 2 minutes
- Rate limit warnings
- Queue depth > 50 tasks

**Info Alerts (Slack):**
- Daily summary of tasks processed
- Weekly cost reports
- Unusual patterns detected

## Testing Strategy

### Unit Tests

**Test Coverage Areas:**
1. Context gathering logic
2. Prompt template generation
3. Tool execution routing
4. Error handling and retries
5. Result parsing and validation

**Example Test:**
```typescript
describe('AgentOrchestrator', () => {
  describe('executeTask', () => {
    it('should successfully triage a Linear issue', async () => {
      const mockTask = createMockLinearTriageTask();
      const orchestrator = new AgentOrchestrator(mockConfig);

      const result = await orchestrator.executeTask(mockTask);

      expect(result.success).toBe(true);
      expect(result.actions).toHaveLength(3);
      expect(result.actions[0].type).toBe('label_added');
    });

    it('should enforce concurrency limit', async () => {
      const orchestrator = new AgentOrchestrator({ maxConcurrent: 2 });

      const tasks = [
        orchestrator.executeTask(task1),
        orchestrator.executeTask(task2),
        orchestrator.executeTask(task3)
      ];

      expect(orchestrator.getStatus().activeAgents).toBe(2);
    });

    it('should retry on transient failures', async () => {
      const mockTool = jest.fn()
        .mockRejectedValueOnce(new RateLimitError())
        .mockResolvedValueOnce({ success: true });

      const result = await orchestrator.executeWithRetry(mockTool);

      expect(mockTool).toHaveBeenCalledTimes(2);
      expect(result.success).toBe(true);
    });
  });
});
```

### Integration Tests

**Test Scenarios:**
1. End-to-end Linear triage flow with real API
2. Slack message → Linear issue creation
3. GitHub PR review with multiple comments
4. MCP server failure and recovery
5. Concurrent task execution

**Test Environment:**
- Use Linear/Slack/GitHub test workspaces
- Separate test database
- Mock Anthropic API or use separate key
- Isolated MCP server instances

### Load Tests

**Objectives:**
- Determine max concurrent agents without degradation
- Measure queue processing throughput
- Identify bottlenecks (API limits, database, memory)
- Validate auto-scaling behavior

**Test Scenarios:**
```typescript
// Scenario 1: Burst Load
- Send 50 tasks within 1 second
- Measure: Queue processing time, success rate
- Expected: All tasks complete within 10 minutes, >95% success

// Scenario 2: Sustained Load
- Send 1 task per second for 1 hour
- Measure: Throughput, latency, error rate
- Expected: Consistent performance, no memory leaks

// Scenario 3: Mixed Priority
- Send P0, P1, P2, P3 tasks intermixed
- Measure: Priority queue ordering, P0 latency
- Expected: P0 tasks complete first, <2 min latency
```

## Security Considerations

### Authentication & Authorization

**API Key Management:**
- Store all keys in environment variables or secret manager
- Rotate keys quarterly (automate with scripts)
- Use separate keys for dev/staging/production
- Principle of least privilege for service accounts

**MCP Server Security:**
- Run MCP servers in isolated processes
- Limit file system access
- Network isolation where possible
- Monitor for suspicious activity

### Input Validation

**Webhook Payload Validation:**
```typescript
- Verify signatures from Linear/Slack/GitHub
- Validate payload schema before processing
- Sanitize user inputs before passing to agent
- Reject malformed or suspicious requests
```

**Tool Input Validation:**
```typescript
- Validate all tool inputs before execution
- Sanitize strings to prevent injection
- Validate resource IDs exist before operations
- Check permissions before destructive operations
```

### Audit Trail

**What to Log:**
- All task executions with full context
- Every tool call with inputs/outputs
- All actions taken on external systems
- Authentication attempts and failures
- Configuration changes

**Retention Policy:**
- Operational logs: 30 days
- Audit logs: 1 year
- Critical events: 7 years
- Cost/metrics: 2 years

### Rate Limiting

**Agent-Level Limits:**
- Max 50 tool calls per task
- Max 10 minutes execution time
- Max 3 concurrent agents per user/source

**Platform-Level Limits:**
```typescript
Linear API: 1000 requests/hour
Slack API: 50 messages/minute per channel
GitHub API: 5000 requests/hour
Anthropic API: Based on account tier
```

**Circuit Breaker:**
```typescript
- Open circuit if error rate > 50% over 1 minute
- Half-open state after 30 seconds
- Close circuit if 3 consecutive successes
```

## Deployment Architecture

### Infrastructure Components

```yaml
Services:
  - agent-orchestrator:
      type: Node.js application
      replicas: 2 (HA)
      resources:
        cpu: 1 core
        memory: 2GB

  - redis:
      type: Queue + Cache
      replicas: 1 (managed service)

  - postgresql:
      type: Database
      replicas: 1 (managed service)

  - mcp-servers:
      type: Sidecar containers
      lifecycle: Per-agent spawned

Networking:
  - Load balancer for webhook ingestion
  - Internal service mesh for orchestrator ↔ MCP
  - Egress for API calls (Linear, Slack, GitHub)
```

### Scaling Strategy

**Horizontal Scaling:**
- Run multiple orchestrator instances
- Use Redis for distributed queue
- PostgreSQL for shared state
- Load balance webhook ingestion

**Vertical Scaling:**
- Increase memory for larger context
- More CPU for parallel tool execution
- SSD for faster database access

**Auto-Scaling Rules:**
```typescript
Scale up if:
  - Queue depth > 20 tasks for 5 minutes
  - CPU usage > 70% for 5 minutes
  - Average response time > 2 minutes

Scale down if:
  - Queue depth = 0 for 15 minutes
  - CPU usage < 30% for 15 minutes
  - Active agents = 0 for 10 minutes

Min replicas: 1
Max replicas: 10
```

### Deployment Process

**CI/CD Pipeline:**
```yaml
1. Code pushed to main branch
2. Run unit tests + linting
3. Build Docker image
4. Run integration tests
5. Deploy to staging environment
6. Run smoke tests
7. Manual approval (for production)
8. Blue-green deployment to production
9. Health checks
10. Route traffic to new version
```

**Health Checks:**
```typescript
// Liveness probe
GET /health
Response: 200 OK if process running

// Readiness probe
GET /health/ready
Response: 200 OK if:
  - Database connection healthy
  - Redis connection healthy
  - At least 1 MCP server responsive
  - Can spawn new agent
```

## Cost Estimation

### Anthropic API Costs

**Model Pricing (Claude Sonnet 4.5):**
- Input: $3 per million tokens
- Output: $15 per million tokens

**Estimated Usage Per Task:**
```
Linear Triage:
  - Input: ~5,000 tokens (context + conversation)
  - Output: ~2,000 tokens (responses + tool calls)
  - Cost per task: $0.045

Slack Bug Analysis:
  - Input: ~7,000 tokens
  - Output: ~3,000 tokens
  - Cost per task: $0.066

GitHub PR Review:
  - Input: ~15,000 tokens (code diff)
  - Output: ~5,000 tokens
  - Cost per task: $0.120

Average: ~$0.05 per task
```

**Monthly Projections:**
```
Scenario: 100 tasks/day
  - Total tasks/month: 3,000
  - API cost: $150/month

Scenario: 500 tasks/day
  - Total tasks/month: 15,000
  - API cost: $750/month

Scenario: 1000 tasks/day
  - Total tasks/month: 30,000
  - API cost: $1,500/month
```

### Infrastructure Costs

**AWS Pricing (example):**
```
- ECS/Fargate (2 instances): $50/month
- RDS PostgreSQL (db.t3.small): $30/month
- ElastiCache Redis: $15/month
- Application Load Balancer: $20/month
- Data transfer: $10/month
- CloudWatch logs: $10/month

Total infrastructure: ~$135/month
```

**Total Monthly Cost Estimate:**
- 100 tasks/day: $285/month
- 500 tasks/day: $885/month
- 1000 tasks/day: $1,635/month

### Cost Optimization Strategies

1. **Use Haiku for Simple Tasks:**
   - Linear label classification: Use Haiku ($0.25/$1.25 per MTok)
   - Save ~80% on simple tasks

2. **Batch Similar Tasks:**
   - Triage multiple issues in single conversation
   - Amortize context cost across items

3. **Cache Common Context:**
   - Team info, labels, user lists
   - Reduce redundant API fetches

4. **Implement Prompt Caching:**
   - Use Anthropic's prompt caching for repeated context
   - Save on input tokens

## Open Questions & Decisions Needed

### Technical Decisions

1. **Agent SDK vs Direct API?**
   - Recommendation: Start with SDK, migrate if needed
   - Need: Validate SDK supports our use cases
   - Timeline: Decide by end of week

2. **Workflow Engine Integration?**
   - Should orchestrator integrate with Temporal/Step Functions?
   - Or remain standalone with internal state?
   - Recommendation: Start standalone, add workflow later

3. **MCP Server Lifecycle?**
   - Shared MCP servers vs per-agent instances?
   - Recommendation: Shared with connection pooling
   - Need: Test concurrency limits

4. **Codebase Access?**
   - How do agents access code for analysis?
   - Git clone per task? Shared workspace? API?
   - Recommendation: Shared read-only workspace + git API

### Business Decisions

1. **Human Approval Gates?**
   - Which actions require human approval?
   - Recommendation: Start with all actions requiring approval, relax over time
   - Examples:
     - Creating PRs: Yes (initially)
     - Triaging issues: No
     - Posting to Slack: No (unless @mentioning)

2. **Error Handling Policy?**
   - When should agent ask for help vs fail?
   - When to escalate to humans?
   - Recommendation: Ask for help after 2 tool failures

3. **Cost Limits?**
   - Per-task cost limits?
   - Daily/monthly budget caps?
   - Recommendation: $0.50 per task limit, $1000/month cap initially

### Operational Decisions

1. **Rollout Strategy?**
   - Which use case to start with?
   - Recommendation: Linear triage (lowest risk)
   - Timeline: 1 week MVP, 2 weeks beta, 1 week GA

2. **Monitoring & Alerting?**
   - What observability tools to use?
   - Recommendation: DataDog or similar
   - Integration: Sentry for errors, Slack for alerts

3. **Team Ownership?**
   - Who maintains this system?
   - Who responds to alerts?
   - Recommendation: Platform team owns, rotating on-call

## MVP Implementation Plan

### Phase 1: Core Infrastructure (Week 1)

**Goals:**
- Basic agent orchestrator working
- Can execute single Linear triage task
- Manual testing only

**Tasks:**
```
1. Project setup
   - Initialize Node.js TypeScript project
   - Install dependencies (Anthropic SDK, MCP)
   - Configure development environment

2. Implement AgentOrchestrator class
   - Basic task queue (in-memory)
   - Single agent execution
   - Context gathering for Linear

3. Implement Linear triage flow
   - Fetch issue via MCP
   - Build triage prompt
   - Execute conversation loop
   - Handle tool calls (update issue, add comment)

4. Manual testing
   - Trigger on test Linear issue
   - Verify correct labeling
   - Check comment quality
```

**Success Criteria:**
- Can manually trigger triage for Linear issue
- Agent successfully updates issue
- No crashes or errors

### Phase 2: Production Infrastructure (Week 2)

**Goals:**
- Add webhook ingestion
- Add PostgreSQL for state
- Add Redis for queue
- Deploy to staging

**Tasks:**
```
1. Webhook gateway
   - Express server with Linear webhook endpoint
   - Signature verification
   - Enqueue to Redis

2. Database schema
   - Task table
   - Action audit log table
   - Migrations

3. Queue worker
   - Pull from Redis
   - Execute via orchestrator
   - Update database with results

4. Deployment
   - Dockerize application
   - Deploy to staging (Railway/Render)
   - Configure MCP servers
   - Set up Linear webhook
```

**Success Criteria:**
- Webhook triggers automatic triage
- Tasks stored in database
- Can monitor via logs

### Phase 3: Monitoring & Reliability (Week 3)

**Goals:**
- Add observability
- Implement error handling
- Add metrics and alerts
- Beta testing

**Tasks:**
```
1. Logging
   - Structured logging (Winston/Pino)
   - Log aggregation (DataDog/CloudWatch)

2. Metrics
   - Prometheus metrics
   - Grafana dashboards
   - Key performance indicators

3. Error handling
   - Retry logic
   - Circuit breaker
   - Dead letter queue

4. Beta testing
   - Enable for specific Linear projects
   - Monitor closely
   - Gather feedback
```

**Success Criteria:**
- >90% success rate on beta projects
- <5 minute average execution time
- No critical errors for 1 week

### Phase 4: Expansion (Week 4+)

**Goals:**
- Add Slack bug analysis
- Add GitHub PR review
- Production rollout

**Tasks:**
```
1. Slack integration
   - Webhook endpoint
   - Context gathering
   - Message posting

2. GitHub integration
   - Webhook endpoint
   - PR fetching
   - Review posting

3. Production rollout
   - Enable for all Linear projects
   - Add Slack channels gradually
   - Monitor costs and performance
```

## Success Metrics

### Technical Metrics

**Performance:**
- Average task execution time: <2 minutes
- P95 execution time: <5 minutes
- Queue processing throughput: >100 tasks/hour

**Reliability:**
- Task success rate: >95%
- Uptime: >99.5%
- Error rate: <5%

**Efficiency:**
- Average API cost per task: <$0.10
- Tool calls per task: <20
- Context gathering time: <10 seconds

### Business Metrics

**Linear Triage:**
- % issues triaged within 1 hour: >80%
- % issues with correct labels: >90%
- % issues with correct priority: >85%

**Slack Bug Analysis:**
- % valid bugs converted to Linear: >70%
- Average response time: <5 minutes
- % bugs requiring clarification: <30%

**GitHub PR Review:**
- % PRs reviewed within 1 hour: >60%
- % reviews with actionable feedback: >50%
- False positive rate: <20%

### User Satisfaction

**Surveys:**
- Agent usefulness rating: >4/5
- Would recommend: >80%
- Time saved per week: >2 hours

**Behavioral:**
- Agent comments upvoted: >60%
- Agent suggestions accepted: >70%
- Manual overrides: <20%

## Future Enhancements

### Short-term (1-3 months)

1. **Multi-agent Collaboration**
   - Multiple agents working on same task
   - Specialized agents per domain (frontend, backend, infra)
   - Agent handoff and delegation

2. **Learning & Improvement**
   - Track which actions get reverted/modified
   - Adjust prompts based on outcomes
   - Build knowledge base from past decisions

3. **Advanced Workflows**
   - Auto-create PR for specific issue types
   - End-to-end bug fix (analyze → fix → test → PR)
   - Scheduled triage runs (daily summaries)

### Long-term (3-6 months)

1. **Proactive Actions**
   - Detect patterns in issues (recurring bugs)
   - Suggest refactors based on bug clusters
   - Auto-triage based on historical data

2. **Code Generation**
   - Generate boilerplate code for features
   - Auto-fix simple bugs
   - Write tests for new code

3. **Integration Expansion**
   - Sentry error analysis
   - Datadog incident response
   - PagerDuty alert triage
   - Jira/Asana support

4. **Advanced Analytics**
   - Team productivity insights
   - Issue lifecycle analysis
   - Cost vs value tracking
   - ROI reporting

## Appendix

### Glossary

- **Agent:** An instance of Claude AI executing a specific task
- **Context:** Data gathered before agent execution (issue details, related info)
- **Orchestrator:** System managing agent lifecycle and execution
- **MCP:** Model Context Protocol - standard for connecting AI to data sources
- **Tool:** Function that agent can call (update issue, post comment, etc.)
- **Task:** Unit of work for an agent (triage issue, review PR)
- **Action:** Concrete operation taken by agent (added label, posted comment)

### References

- **Anthropic API Documentation:** https://docs.anthropic.com/
- **Claude Agent SDK:** https://github.com/anthropics/anthropic-sdk-typescript
- **MCP Specification:** https://modelcontextprotocol.io/
- **Linear API:** https://developers.linear.app/
- **Slack API:** https://api.slack.com/
- **GitHub API:** https://docs.github.com/en/rest

### Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-18 | Claude | Initial design document |

---

**Next Steps:**
1. Review and approve this design with team
2. Begin Phase 1 implementation
3. Set up project repository and infrastructure
4. Schedule weekly sync to track progress
