# Milhouse UI Design Rules

Design principles and best practices for building a best-in-class TUI (Terminal User Interface) using `gum`. These rules should be followed when implementing Milhouse's user interface.

## Core Design Principles

### 1. Clarity First
- Use literal text for actions rather than cryptic icons
- Labels like "Confirm", "Cancel", "Next" are preferable to glyphs unless meaning is obvious
- Make error messages descriptive: explain *what* went wrong *and how* to resolve it
- Action names should be verbs in plain English (e.g., "Delete file" not "rm_f")

### 2. Consistent Theming & Styling
- Define a theme (colors, border styles, margins) and use it consistently across all gum commands
- Establish spacing, alignment, and padding rules so elements feel part of the same UI family
- Use `gum style` for consistent formatting
- Support global theme via environment variables while allowing per-command overrides

### 3. Graceful Degradation & Width Sensitivity
- Detect terminal width/height; don't assume minimum sizes
- Wrap or crop content where necessary for small terminals
- Avoid layouts that break or overflow in small terminals
- Use vertical stacks rather than wide layouts when space is limited
- If `gum` is not installed, fallback to plain prompts and outputs seamlessly

### 4. Informative Feedback & Progress Indication
- Provide spinners (`gum spin`) for long-running tasks so users know something is happening
- Show progress indicators for operations that take time
- After actions (especially destructive ones), explicitly show success or error feedback
- Visualize live state changes (progress bars, counts, status messages) rather than only final outputs
- At workflow end, show summarized results: what was done, any failures, etc.

### 5. Forgiving User Input & Prompts
- Use placeholders and default values for inputs (`gum input --placeholder`)
- Allow canceling operations easily (Ctrl+C should always work)
- For filtered lists, allow fuzzy matching and multi-select when relevant
- Accept variations (whitespace, casing) where possible
- Provide meaningful error messages with actionable guidance

### 6. Minimal Dependency & Simplicity
- Use gum's built-in commands (`style`, `join`, `format`) instead of orchestrating many tools
- Fewer moving parts = easier maintenance
- Avoid overusing complex layouts unless they add clarity
- A simple vertical flow is often most usable
- Keep prompts short; reduce cognitive load

### 7. Customizability without Complexity
- Expose style flags (colors, width, borders, etc.) for power users
- Support environment variables for global theming defaults
- Maintain sensible defaults so non-custom users get a polished experience out of the box
- Don't require configuration to be useful

### 8. Accessible & Inclusive Design
- Use readable color contrasts; avoid color combinations difficult for colorblind users
- Use plain, direct language; avoid jargon
- Ensure interactive elements have clear focus states or indicators
- Don't assume terminal supports fancy Unicode or wide emoji
- Test across different terminals if possible

### 9. Visual Hierarchy & Structure
- Separate status, main content, and prompts visually
- Use spacing, borders, and alignment to define hierarchy
- Use borders/padding to organize content (header, body, footer)
- Highlight important parts (errors, notifications)
- Use monospace only for code or structured output; avoid mixing styles that break alignment

### 10. Progressive Disclosure
- Don't display information the user doesn't need right now
- Let complexity unfold only when needed
- Defaults should be smart; minimize required input
- If only one option is valid, auto-select or skip prompt

### 11. Stateful Operations
- Show task status live: progress of operations
- Provide summary of actions after operation finishes
- For destructive actions, require explicit confirmation (`gum confirm`)
- Allow cancellation at any point where it makes sense

### 12. Modular UI Construction
- Build complex flows by combining simple gum commands
- Use `gum choose`, `gum confirm`, `gum filter`, `gum input`, etc. as building blocks
- No ad-hoc ANSI art; use gum components for all UI pieces
- Compose larger interfaces from smaller, focused components

## Implementation Guidelines

### For Milhouse Specifically

1. **Model Selection**
   - Use `gum choose` for model selection
   - Show current/default selection clearly
   - Allow "Custom" option with `gum input` fallback

2. **Configuration Prompts**
   - Use `gum input` with placeholders for text input
   - Use `gum confirm` for yes/no decisions
   - Use `gum choose --no-limit` for multi-select options

3. **Progress & Status**
   - Use `gum spin` for long-running operations (agent working)
   - Use `gum style` for status messages with appropriate colors
   - Show iteration progress clearly with borders/styling

4. **Error Handling**
   - Format errors with `gum style --foreground red` or similar
   - Provide actionable next steps in error messages
   - Don't use jargon or technical error codes without explanation

5. **Completion & Success**
   - Show clear success indicators with green styling
   - Summarize what was accomplished
   - Provide next steps or options

### Color Guidelines

- **Success**: Green foreground (`--foreground 10` or similar)
- **Error**: Red foreground (`--foreground 1`)
- **Warning**: Yellow/orange (`--foreground 3`)
- **Info**: Blue/cyan (`--foreground 12`)
- **Borders**: Subtle, not overwhelming (`--border-foreground` with lower contrast)

### Spacing & Layout

- Use consistent padding (`--padding "0 1"` or `--padding "0 2"`)
- Vertical spacing between sections
- Horizontal alignment where it helps readability
- Don't crowd elements; give breathing room

### Fallback Strategy

When `gum` is not available:
- Use simple `read -p` for input
- Use `echo` with clear formatting for output
- Maintain same information architecture
- Never fail due to missing `gum`; degrade gracefully

## Example Patterns

### Status Message
```bash
gum style --border double --padding "0 2" --border-foreground 212 "Status: Running iteration 3"
```

### Confirmation
```bash
gum confirm "Start Milhouse loop?" && start_loop || exit 0
```

### Multi-select with Headers
```bash
gum choose --no-limit --header "Select options:" "Option 1" "Option 2" "Option 3"
```

### Progress Indicator
```bash
gum spin --spinner dot --title "Agent working..." -- sleep 10
```

### Error Display
```bash
gum style --foreground 1 --border double --padding "0 1" "Error: Task file not found. Create MILHOUSE_TASK.md first."
```

## References

- [gum GitHub Repository](https://github.com/charmbracelet/gum)
- TUI/CLI UX best practices
- Terminal accessibility guidelines

## Notes

- These rules should be referenced when implementing any UI component in Milhouse
- Prefer consistency over cleverness
- When in doubt, choose the simpler, clearer option
- Test in minimal terminals to ensure graceful degradation
