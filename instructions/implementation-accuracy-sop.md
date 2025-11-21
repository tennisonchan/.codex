# Implementation Accuracy SOP

## When to use
- Any ticket where the primary risk is fidelity to specs (product requirements, design mocks, migration steps).
- Work that must avoid scope creep or unintended side effects (UI or backend).

## Steps
1) **Extract acceptance checklist** before coding:
   - Copy target behaviors from ticket/design/spec into a checklist of outcomes and explicit "must nots".
   - Include scope boundaries (e.g., fonts only, no layout; endpoint contract unchanged; no DB shape changes).
2) **Plan with the checklist**: write the checklist into the task log/PR description; align the work plan to cover each item.
3) **Guardrails during implementation**:
   - Touch only files/components required by the checklist.
   - Reuse existing tokens/helpers; avoid ad-hoc values or new patterns unless specified.
   - When something forces scope expansion, pause and confirm requirements.
4) **Self-review against the checklist**:
   - `git diff` scan for out-of-scope changes (new class names, layout props, schema changes, etc.).
   - Verify each acceptance item; mark checked/annotate with proof (link to screenshot/log/test).
5) **Evidence**:
   - Add quick proof for risk areas (screenshot for UI, log/test snippet for backend).
   - Note any intentional deviations and approvals in the task log/PR.
6) **PR notes**: include the checklist with statuses and explicit statement about scope adherence.
