# Webhook-to-Codex Automation Implementation Plan
**Updated:** 2025-11-18
**Status:** Design Phase - Ready for Implementation

## At a Glance
- Goal: convert external webhooks (Linear/Slack/GitHub/Sentry) into routed Codex tasks via a thin gateway + dispatcher.
- MVP slice: one end-to-end scenario proving ingestion → queue → dispatcher → agent orchestration.
- Next decisions: pick queue tech (Redis vs SQS) and finalize signature verification libs per source.
- Owner: Platform/Infra (agent orchestrator team).

## Objectives
- Provide a repeatable path from external webhooks (Linear, Slack, GitHub) to actionable Codex work
- Keep ingestion, routing, and execution loosely coupled so each layer can scale independently
- Deliver a minimal deployable slice that proves end-to-end automation for one scenario before expanding
- Use **Codex CLI processes** for strong isolation and access to full Claude Code capabilities

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Webhook Sources                            │
│         Linear │ Slack │ GitHub │ Sentry                      │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│                  Webhook Gateway                              │
│  - Signature verification                                     │
│  - Payload normalization                                      │
│  - Event storage + enqueueing                                 │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│               Event Queue (Redis/SQS)                         │
│  - Durable storage with DLQ                                   │
│  - Priority-based processing                                  │
│  - Deduplication                                              │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│                 Dispatcher Service                            │
│  - Fetch fresh context via MCP/APIs                          │
│  - Apply routing rules                                        │
│  - Enrich event with context                                 │
│  - Create agent task                                          │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│              Agent Orchestrator                               │
│  - Workspace management                                       │
│  - Codex CLI process spawning                                │
│  - Output parsing & validation                               │
│  - Result processing                                          │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│    Codex CLI Worker Processes (Isolated Execution)           │
│  - Individual claude-code processes                           │
│  - Per-task workspaces with MCP servers                      │
│  - Context files + prompts                                    │
│  - Structured output (result.json)                           │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│         Platform APIs (via MCP or Direct)                     │
│  Linear │ Slack │ GitHub │ Codebase Access                   │
└──────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### 1. Webhook Gateway

**Technology:** Fastify/Express server

**Responsibilities:**
- Host `/webhooks/linear`, `/webhooks/slack`, `/webhooks/github` endpoints
- Verify webhook signatures (HMAC-SHA256)
- Normalize payloads into shared schema
- Store raw webhooks in PostgreSQL for audit
- Enqueue event ID to Redis/SQS for async processing
- Return 200 OK within 3 seconds

**Implementation:**
```typescript
// POST /webhooks/linear
app.post('/webhooks/linear', async (req, res) => {
  // 1. Verify signature
  const isValid = verifyLinearSignature(req.headers, req.body);
  if (!isValid) return res.status(401).send('Invalid signature');

  // 2. Store raw event
  const eventId = await db.events.create({
    source: 'linear',
    type: req.body.type,
    payload: req.body,
    receivedAt: new Date()
  });

  // 3. Enqueue for processing
  await queue.enqueue('webhook-events', {
    eventId,
    priority: calculatePriority(req.body)
  });

  // 4. Quick response
  res.status(200).json({ eventId, queued: true });
});
```

**Rate Limiting:**
- 1000 requests/hour per webhook source
- Circuit breaker on repeated failures

### 2. Event Store & Queue

**Technology:** PostgreSQL (storage) + Redis (queue) OR AWS SQS

**Schema:**
```sql
CREATE TABLE webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL, -- 'linear', 'slack', 'github'
  type TEXT NOT NULL,   -- 'issue.created', 'message.posted', etc.
  payload JSONB NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  status TEXT DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
  retry_count INTEGER DEFAULT 0,
  error_message TEXT,
  task_id UUID REFERENCES agent_tasks(id)
);

CREATE INDEX idx_events_status ON webhook_events(status, received_at);
CREATE INDEX idx_events_source_type ON webhook_events(source, type);
```

**Queue Features:**
- Priority levels (0=highest for P0 bugs, 3=lowest)
- Dead Letter Queue for failed events
- Deduplication (same event within 5 minutes)
- Replay capability (can reprocess events)

### 3. Dispatcher Service

**Technology:** Node.js worker process

**Responsibilities:**
- Poll queue for pending events
- Fetch fresh context from platform APIs
- Apply routing rules (which task type?)
- Check authorization/approval requirements
- Create enriched AgentTask
- Hand off to Agent Orchestrator

**Routing Logic:**
```typescript
class EventRouter {
  async routeEvent(event: WebhookEvent): Promise<AgentTask | null> {
    switch (`${event.source}:${event.type}`) {
      case 'linear:issue.created':
      case 'linear:issue.updated':
        return this.createLinearTriageTask(event);

      case 'slack:message.channels':
        // Only if in #bugs channel
        if (event.payload.channel === BUGS_CHANNEL_ID) {
          return this.createSlackBugAnalysisTask(event);
        }
        return null;

      case 'github:pull_request.opened':
      case 'github:pull_request.synchronize':
        return this.createGitHubReviewTask(event);

      default:
        logger.warn('Unhandled event type', { event });
        return null;
    }
  }

  async createLinearTriageTask(event: WebhookEvent): Promise<AgentTask> {
    const issueId = event.payload.data.id;

    // Fetch context via Linear MCP
    const context = await this.gatherLinearContext(issueId);

    return {
      id: uuidv4(),
      type: 'linear_triage',
      source: 'linear',
      priority: this.calculatePriority(context.issue),
      context: {
        resourceId: issueId,
        issue: context.issue,
        related: context.relatedIssues,
        team: context.teamConfig
      },
      timeout: 300000, // 5 minutes
      requiresCodebase: false
    };
  }
}
```

**Context Gathering:**
```typescript
class ContextGatherer {
  async gatherLinearContext(issueId: string) {
    // Parallel API fetches
    const [issue, relatedIssues, teamConfig, labels] = await Promise.all([
      this.linear.getIssue(issueId),
      this.linear.findRelatedIssues(issueId, { limit: 5 }),
      this.linear.getTeam(),
      this.linear.getLabels()
    ]);

    return { issue, relatedIssues, teamConfig, labels };
  }
}
```

### 4. Agent Orchestrator

**Technology:** Node.js service managing Codex CLI processes

**Responsibilities:**
- Manage concurrent Codex CLI executions
- Create isolated workspaces per task
- Prepare context files and prompts
- Spawn and monitor `claude-code` processes
- Parse output and extract results
- Handle timeouts and failures
- Cleanup workspaces

**Key Components:**

#### 4.1 Workspace Manager
Creates isolated filesystem workspaces:
```
/tmp/codex-tasks/task-{uuid}/
├── workspace/              # Codex working directory
│   ├── .claude/
│   │   ├── config.toml    # MCP servers configuration
│   │   └── auth.json      # Credentials
│   └── repo/              # Git repo (if needed)
├── context/               # Input context files
│   ├── issue.json
│   ├── related.json
│   └── team.json
├── prompts/
│   └── triage.md          # Task-specific prompt
└── outputs/
    ├── result.json        # Structured output
    ├── log.txt            # Execution log
    └── artifacts/         # Screenshots, files
```

#### 4.2 Process Manager
Spawns Codex CLI processes:
```bash
claude-code \
  --workspace /tmp/codex-tasks/task-123/workspace \
  --prompt-file /tmp/codex-tasks/task-123/prompts/triage.md \
  --non-interactive \
  --json-output /tmp/codex-tasks/task-123/outputs/result.json
```

**Monitoring:**
- Capture stdout/stderr in real-time
- Enforce timeout (kill process after N minutes)
- Track tool calls and API usage
- Emit events for monitoring

#### 4.3 Output Parser
Parses `result.json`:
```json
{
  "issueId": "PROJ-123",
  "success": true,
  "actions": [
    {
      "type": "labels_added",
      "labels": ["bug", "backend"],
      "reasoning": "Issue describes a server error with stack trace"
    },
    {
      "type": "priority_set",
      "priority": 1,
      "reasoning": "Affecting production users, high severity"
    },
    {
      "type": "comment_posted",
      "commentId": "abc123",
      "summary": "Triaged as P1 backend bug"
    }
  ],
  "analysis": {
    "type": "bug",
    "severity": "P1",
    "component": "backend",
    "complexity": 3
  }
}
```

**Concurrency Control:**
- Max 3 concurrent Codex processes
- Queue additional tasks
- Resource limits per process (2GB memory, 1 CPU)

### 5. Codex CLI Worker Execution Model

**Approach:** Process-per-task isolation

**Execution Flow:**
1. Orchestrator receives AgentTask
2. Create workspace with context files
3. Generate task-specific prompt
4. Copy MCP server configuration
5. Spawn `claude-code` process
6. Monitor execution (stream logs)
7. Wait for completion or timeout
8. Parse `result.json` output
9. Extract actions taken
10. Cleanup workspace (or archive for debugging)

**Prompt Template Example (Linear Triage):**
```markdown
# Linear Issue Triage Task

You are triaging Linear issue {{issue.identifier}}.

## Context Files

Read these JSON files for context:
- $CONTEXT_DIR/issue.json - Full issue details
- $CONTEXT_DIR/related.json - Related issues
- $CONTEXT_DIR/team.json - Team labels, priorities, states

## Your Tasks

1. Read context files using the Read tool
2. Analyze the issue to determine:
   - Type: bug, feature, enhancement, tech-debt
   - Severity: P0 (critical), P1 (high), P2 (medium), P3 (low)
   - Component: frontend, backend, api, infra
   - Complexity: 1-5

3. Update Linear using MCP tools:
   - mcp__linear__update_issue - Add labels and priority
   - mcp__linear__create_comment - Post triage analysis

4. Write output to $OUTPUT_DIR/result.json with this structure:
{
  "issueId": "...",
  "success": true,
  "actions": [...],
  "analysis": {...}
}

## Guidelines
- Be thorough but concise
- Use team's existing labels
- Reference similar past issues
- Note any missing information
```

**Environment Variables:**
```bash
CONTEXT_DIR=/tmp/codex-tasks/task-123/context
OUTPUT_DIR=/tmp/codex-tasks/task-123/outputs
ANTHROPIC_API_KEY=sk-ant-...
```

### 6. Connectors & Integrations

**MCP Servers Used:**
- `@modelcontextprotocol/server-linear` - Linear API integration
- `@modelcontextprotocol/server-slack` - Slack API integration
- `@modelcontextprotocol/server-github` - GitHub API integration
- `@modelcontextprotocol/server-sentry` (future) - Error tracking

**Direct API Clients:**
- Used by Dispatcher for context gathering
- Used for operations not supported by MCP
- Fallback if MCP unavailable

### 7. Knowledge Management

**Persist Execution History:**
```
docs/tasks/
├── 2025-11-18-linear-PROJ-123-triage.md
├── 2025-11-18-slack-bug-analysis-ts1234.md
└── 2025-11-18-github-pr-456-review.md

docs/context/
├── linear-team-config.md (updated weekly)
├── slack-channels.md
└── common-issues.md (learned patterns)
```

**Format:**
```markdown
# Linear Issue PROJ-123 Triage
**Date:** 2025-11-18
**Task ID:** task-abc-123
**Status:** Completed

## Context
- Issue: "API returns 500 on /users endpoint"
- Reporter: john@company.com
- Created: 2025-11-18 10:00

## Agent Actions
1. Added labels: bug, backend, api
2. Set priority: P1
3. Posted comment with analysis

## Analysis
- Type: Bug
- Severity: P1 (production impact)
- Component: Backend API
- Root cause: Database connection timeout
- Complexity: 3

## Outcome
- Issue properly triaged
- Team notified in Slack
- Assigned to backend team
```

## Data Flow (End-to-End)

**Example: Linear Issue Created**

```
1. Linear Webhook → POST /webhooks/linear
   Payload: { type: 'issue.created', data: { id: 'PROJ-123', ... } }

2. Webhook Gateway
   - Verify signature ✓
   - Store event in DB (id: evt-001)
   - Enqueue to Redis: { eventId: 'evt-001', priority: 2 }
   - Return 200 OK

3. Dispatcher (polling queue)
   - Dequeue event evt-001
   - Fetch context:
     * Issue details via Linear API
     * Related issues (similar titles)
     * Team configuration (labels, states)
   - Create AgentTask:
     {
       id: 'task-abc',
       type: 'linear_triage',
       context: { issue, related, team }
     }
   - Hand to Orchestrator

4. Agent Orchestrator
   - Create workspace: /tmp/codex-tasks/task-abc/
   - Write context files (issue.json, related.json, team.json)
   - Generate prompt from template
   - Copy .claude/config.toml with MCP servers
   - Spawn Codex CLI:
     claude-code --workspace ... --prompt-file ... --json-output ...

5. Codex CLI Process
   - Initialize MCP servers (Linear, Slack, GitHub)
   - Read prompt
   - Read context files
   - Analyze issue
   - Call mcp__linear__update_issue (add labels)
   - Call mcp__linear__update_issue (set priority)
   - Call mcp__linear__create_comment (post analysis)
   - Write result.json
   - Exit 0

6. Orchestrator (post-execution)
   - Parse result.json
   - Extract actions: [labels_added, priority_set, comment_posted]
   - Update DB:
     * task status = completed
     * actions logged
     * metrics recorded
   - Cleanup workspace
   - Emit 'task:completed' event

7. Notifications
   - Post to Slack: "Triaged PROJ-123 as P1 backend bug"
   - Update Linear (already done by Codex)
   - Archive task log to docs/tasks/

Total time: ~30 seconds (webhook → completion)
```

## Operational Considerations

### Security & Compliance

**Webhook Security:**
- Verify all webhook signatures (Linear, Slack, GitHub use HMAC-SHA256)
- Rate limiting (1000 req/hour per source)
- IP allowlisting (optional)

**Secrets Management:**
- Store in environment variables or AWS Secrets Manager
- Rotate API keys quarterly
- Least-privilege tokens:
  * Linear: Read issues + write comments + update issues
  * Slack: Read messages + post messages (no admin)
  * GitHub: Read repos + write comments (no push)
- Separate keys for dev/staging/production

**Workspace Isolation:**
- Each Codex process runs in separate workspace
- No shared state between tasks
- Aggressive cleanup (delete after completion)
- Archive artifacts to S3 for audit (30 day retention)

**Code Access:**
- Read-only repo clones
- No write access to main/master branches
- Use git worktree for PR creation (isolated branches)

### Observability

**Logging:**
```typescript
// Structured JSON logs
{
  timestamp: '2025-11-18T10:30:00Z',
  level: 'info',
  service: 'agent-orchestrator',
  event: 'task.completed',
  taskId: 'task-abc',
  taskType: 'linear_triage',
  duration: 28000,
  success: true,
  actions: 3,
  toolCalls: 7,
  cost: 0.047
}
```

**Metrics (Prometheus/DataDog):**
- `webhook.received.total` (counter)
- `task.execution.duration` (histogram)
- `task.execution.success_rate` (gauge)
- `codex.process.active` (gauge)
- `codex.process.failures` (counter)
- `api.cost.total` (counter)

**Alerts:**
- Slack #dev-alerts for failures
- PagerDuty for >5 consecutive failures
- Weekly summary reports

**Dashboards:**
- Task throughput (tasks/hour)
- Success rate over time
- P95 latency
- Cost per task
- Queue depth

### Error Handling & Retries

**Error Categories:**

1. **Transient (Retry):**
   - API rate limits (429) → Exponential backoff
   - Network timeouts → Retry after 5s
   - MCP server crash → Restart and retry

2. **Permanent (Don't Retry):**
   - Invalid issue ID (404) → Log and skip
   - Insufficient permissions (403) → Alert team
   - Malformed webhook (400) → Log and skip

3. **Agent Failures:**
   - Timeout (>5 min) → Kill process, log, alert
   - Max tool calls (>50) → Stop, ask human
   - Repeated tool failures → Escalate to human

**Retry Strategy:**
```typescript
const retryPolicy = {
  maxAttempts: 3,
  baseDelay: 1000,      // 1 second
  maxDelay: 30000,      // 30 seconds
  backoffMultiplier: 2
};

// Retry with exponential backoff
async function executeWithRetry(fn, policy) {
  for (let attempt = 1; attempt <= policy.maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (!isRetryable(error) || attempt === policy.maxAttempts) {
        throw error;
      }
      const delay = Math.min(
        policy.baseDelay * Math.pow(policy.backoffMultiplier, attempt - 1),
        policy.maxDelay
      );
      await sleep(delay);
    }
  }
}
```

**Dead Letter Queue:**
- Failed events after 3 retries → DLQ
- Manual review in Slack
- Weekly cleanup
- Auto-retry once after 24 hours

### Cost Analysis

**Infrastructure (AWS/Railway):**
```
- Webhook Gateway (1 instance): $15/month
- Orchestrator (1 instance): $25/month
- PostgreSQL (db.t3.micro): $15/month
- Redis/ElastiCache: $15/month
- S3 (artifact storage): $5/month
Total infrastructure: ~$75/month
```

**Anthropic API Costs:**
```
Claude Sonnet 4.5 Pricing:
- Input: $3 per million tokens
- Output: $15 per million tokens

Per Task Estimates:
- Linear triage: ~5K input + 2K output = $0.045
- Slack bug analysis: ~7K input + 3K output = $0.066
- GitHub PR review: ~15K input + 5K output = $0.120
Average: ~$0.05 per task

Monthly Projections:
- 50 tasks/day: ~$80/month
- 200 tasks/day: ~$320/month
- 1000 tasks/day: ~$1,600/month
```

**Total Monthly Cost:**
- 50 tasks/day: $155/month
- 200 tasks/day: $395/month
- 1000 tasks/day: $1,675/month

**Cost Optimization:**
- Use Claude Haiku for simple classification: ~80% cheaper
- Cache common context (team config, labels)
- Batch similar tasks when possible
- Implement prompt caching (Anthropic feature)

## MVP Scope

### Phase 1: Linear Triage (Week 1-2)

**Goal:** Prove end-to-end automation for Linear issue triage

**Implementation:**
1. **Webhook Gateway** (1 day)
   - Fastify server
   - `/webhooks/linear` endpoint
   - Signature verification
   - PostgreSQL event storage
   - Redis queue integration

2. **Dispatcher** (1 day)
   - Event polling from Redis
   - Linear context gathering
   - Task creation

3. **Agent Orchestrator** (2-3 days)
   - Workspace manager
   - Codex CLI process spawner
   - Output parser
   - Basic monitoring

4. **Prompts & Testing** (1-2 days)
   - Linear triage prompt template
   - Integration testing
   - Fix bugs

**Success Criteria:**
- Linear webhook → automatic triage within 2 minutes
- >90% success rate
- Correct labels applied
- Useful triage comments

**Deployment:**
- Railway/Render (simple deployment)
- Single container
- Environment variables for config
- Webhook to staging Linear workspace

### Phase 2: Slack Bug Analysis (Week 3)

**Goal:** Expand to Slack bug reports

**Implementation:**
1. `/webhooks/slack` endpoint
2. Slack context gathering
3. Slack bug analysis prompt
4. Create Linear issues from Slack
5. Post replies in Slack threads

**Success Criteria:**
- Slack message → Linear issue created
- Clarifying questions asked when needed
- >80% valid bug detection

### Phase 3: GitHub PR Review (Week 4)

**Goal:** Automated PR review

**Implementation:**
1. `/webhooks/github` endpoint
2. Repository cloning in workspace
3. GitHub PR review prompt
4. Inline code comments
5. Summary review comments

**Success Criteria:**
- PR opened → review posted within 5 minutes
- Actionable feedback provided
- <20% false positive rate

## Future Enhancements (Post-MVP)

### Short-term (1-3 months)
- **Auto-PR creation** from Linear tickets
- **Sentry integration** for error triage
- **Daily digest** summaries to Slack
- **Human approval gates** for sensitive actions
- **Multi-agent collaboration** (specialized agents)

### Long-term (3-6 months)
- **Proactive monitoring** (detect patterns)
- **Auto-fix simple bugs** (generate PR)
- **Advanced analytics** (ROI tracking)
- **Custom workflows** (visual builder)
- **Self-improving prompts** (learn from feedback)

## Deployment Architecture

### Development
```yaml
services:
  orchestrator:
    image: agent-orchestrator:dev
    environment:
      - NODE_ENV=development
      - DEBUG_KEEP_WORKSPACES=true
    volumes:
      - ./src:/app/src
      - /tmp/codex-tasks:/tmp/codex-tasks

  postgres:
    image: postgres:16
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7
```

### Production
```yaml
services:
  webhook-gateway:
    image: agent-orchestrator:latest
    deploy:
      replicas: 2
      resources:
        limits: { cpus: '1', memory: '1G' }
    environment:
      - NODE_ENV=production
      - MAX_CONCURRENT_PROCESSES=3

  orchestrator:
    image: agent-orchestrator:latest
    deploy:
      replicas: 1
      resources:
        limits: { cpus: '4', memory: '8G' }
    volumes:
      - /tmp/codex-tasks:/tmp/codex-tasks

  postgres:
    image: postgres:16
    deploy:
      resources:
        limits: { cpus: '2', memory: '4G' }

  redis:
    image: redis:7
    deploy:
      resources:
        limits: { cpus: '1', memory: '2G' }
```

## Success Metrics

### Technical
- Task success rate: **>95%**
- Average execution time: **<2 minutes**
- P95 execution time: **<5 minutes**
- System uptime: **>99.5%**
- Queue processing throughput: **>100 tasks/hour**

### Business
- Issues triaged within 1 hour: **>80%**
- Correct label accuracy: **>90%**
- Correct priority accuracy: **>85%**
- Bugs converted to Linear: **>70%**
- PRs reviewed within 1 hour: **>60%**

### User Satisfaction
- Agent usefulness rating: **>4/5**
- Would recommend: **>80%**
- Time saved per week: **>10 hours/team**
- Manual overrides: **<20%**

## Open Questions → Answers

### Q: Which workflow engine best fits existing stack?

**Answer:** **None for MVP**. Start with simple Redis queue + PostgreSQL state management. The overhead of Temporal/Step Functions isn't justified for linear workflows.

**Add workflow engine later if:**
- Multi-step approval flows (>3 steps with human gates)
- Long-running workflows (hours/days)
- Need visual workflow designer
- Complex branching logic

**Recommended future:** Temporal (if self-hosted) or Step Functions (if on AWS)

### Q: How are Codex worker logs/artifacts persisted for audit?

**Answer:**
```
Logs:
- CloudWatch Logs (structured JSON) - 30 days retention
- Critical events → PostgreSQL audit table - 1 year

Artifacts:
- S3 bucket with lifecycle policy:
  * First 30 days: Standard storage
  * 30-90 days: Glacier
  * >90 days: Auto-delete
- Object key: s3://codex-artifacts/{task-id}/{artifact-name}

Conversation History:
- Full Codex CLI output saved to S3
- Used for debugging and improvement
- 30 day retention

Metrics:
- Prometheus + Grafana (long-term storage)
- Cost tracking in PostgreSQL
```

### Q: What human approval thresholds are required?

**Answer:**

**Auto-approve (No human needed):**
- Adding labels to Linear issues ✓
- Setting priority ✓
- Posting triage comments ✓
- Creating Linear issues from Slack ✓
- Posting in Slack threads ✓
- Inline PR review comments ✓

**Require approval:**
- Creating PRs ⚠️
- Merging code ⚠️
- Closing/archiving issues ⚠️
- Deleting anything ⚠️
- @mentioning users outside team ⚠️
- Posting in public Slack channels (not threads) ⚠️
- Modifying production config ⚠️

**Implementation:**
```typescript
async function requiresApproval(action: Action): Promise<boolean> {
  const approvalRequired = [
    'pr_created',
    'pr_merged',
    'issue_closed',
    'mention_user',
    'public_post'
  ];

  return approvalRequired.includes(action.type);
}

// Approval flow
if (await requiresApproval(action)) {
  await postApprovalRequest(action);
  await waitForApproval(action.id, timeout: 24h);
}
```

## Risk Mitigation

### Risk: Codex makes incorrect changes

**Mitigation:**
- Start with read-only operations (triage, comments)
- Require human approval for destructive actions
- Log all actions for audit
- Easy rollback mechanism
- Gradual rollout (10% → 50% → 100%)

### Risk: High API costs

**Mitigation:**
- Set monthly budget cap ($1000 initially)
- Alert at 80% budget
- Use cheaper models for simple tasks
- Implement prompt caching
- Monitor cost per task

### Risk: Process failures/crashes

**Mitigation:**
- Timeout enforcement (kill after 5 min)
- Resource limits (2GB memory per process)
- Retry with exponential backoff
- Dead letter queue for manual review
- Alerting on repeated failures

### Risk: Security breach

**Mitigation:**
- Least-privilege API tokens
- Workspace isolation
- No persistent state
- Regular security audits
- Rotate secrets quarterly
- Monitor for suspicious activity

## Next Steps

1. **Week 1:** Build webhook gateway + dispatcher
2. **Week 2:** Build agent orchestrator with Linear triage
3. **Week 3:** Deploy to staging + testing
4. **Week 4:** Production rollout (10% traffic)
5. **Week 5:** Monitor + iterate
6. **Week 6+:** Expand to Slack and GitHub

**First Milestone:** Successfully triage 100 Linear issues with >90% success rate.

---

**Document Status:** Ready for implementation
**Owner:** Engineering team
**Review Date:** Weekly during MVP phase
