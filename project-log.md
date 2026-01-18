# Project Log

> **Purpose**: Track decisions made, version history of major changes, and questions/issues to resolve.

## Version History

### [2025-01-XX] - Initial Project Setup
- Created project structure
- Established folder hierarchy
- Created template files
- Analyzed Ralph Wiggum architecture
- Created implementation plan (MILHOUSE_PLAN.md)
- Established UI design rules (UI_RULES.md, GUM_TUI_RULES.md)

## Decisions Log

### [2025-01-XX] - Simplified Architecture Approach
**Decision**: Use heuristic-based rotation instead of precise token tracking  
**Rationale**: Achieve 80% of Ralph's functionality with 20% of the complexity by using simpler checks (time, file count, iteration number) instead of real-time JSON stream parsing  
**Impact**: Reduces dependencies (no `jq`), simpler codebase (~300 lines vs ~2000), easier maintenance

### [2025-01-XX] - Single Script Architecture
**Decision**: One main `milhouse.sh` script instead of multiple modules  
**Rationale**: Easier to understand, maintain, and debug. Simpler mental model.  
**Impact**: Single source of truth, no shared state management complexity

### [2025-01-XX] - Git as Audit Trail
**Decision**: Use `git log` and `git diff` for analysis instead of separate activity/error logs  
**Rationale**: Git already tracks changes; no need to duplicate this information  
**Impact**: Fewer files to manage, simpler state, leverages existing tooling

### [2025-01-XX] - Include Gum for UI
**Decision**: Use `gum` for beautiful TUI when available, with graceful fallback  
**Rationale**: Better UX with minimal complexity (optional dependency)  
**Impact**: Polished interface when gum is installed, still works without it

## Questions & Issues

### Open Questions
- [ ] What are optimal thresholds for heuristic rotation? (Time? File count? Iterations?)
- [ ] How to best detect gutter conditions using git log analysis?
- [ ] Should Phase 1 include basic rotation or wait until Phase 2?

### Resolved Issues
- [x] Architecture approach - Decided on heuristic-based simplification - [2025-01-XX]
- [x] UI library choice - Use gum with fallback - [2025-01-XX]

## Notes

- Project is a simplification of Ralph Wiggum technique
- Goal: Same core functionality (autonomous dev with context rotation) with less complexity
- Reference implementation: `ralph-wiggum-cursor/` subdirectory contains original Ralph for comparison
