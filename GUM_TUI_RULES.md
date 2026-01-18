# Gum TUI Design Rules

Design principles and best practices for building best-in-class Terminal User Interfaces (TUIs) using `gum`. These rules apply to any TUI project using gum components.

## Core Design Principles

### 1. Clarity First
- Use literal text for actions rather than cryptic icons or symbols
- Labels like "Confirm", "Cancel", "Next" are preferable to glyphs unless meaning is universally obvious
- Make error messages descriptive: explain *what* went wrong *and how* to resolve it
- Action names should be verbs in plain English (e.g., "Delete file" not "rm_f")
- Avoid jargon unless your audience is technical; provide context when using technical terms

### 2. Consistent Theming & Styling
- Define a theme (colors, border styles, margins) and use it consistently across all gum commands
- Establish spacing, alignment, and padding rules so elements feel part of the same UI family
- Use `gum style` for consistent formatting throughout your application
- Support global theme via environment variables while allowing per-command overrides
- Create a style guide and stick to it; consistency builds trust

### 3. Graceful Degradation & Width Sensitivity
- Detect terminal width/height; don't assume minimum sizes
- Wrap or crop content where necessary for small terminals
- Avoid layouts that break or overflow in small terminals
- Use vertical stacks rather than wide layouts when space is limited
- Always provide a fallback when `gum` is not installed (plain prompts, echo statements)
- Test in terminals of various sizes (80x24 minimum, but prefer responsive)

### 4. Informative Feedback & Progress Indication
- Provide spinners (`gum spin`) for long-running tasks so users know something is happening
- Show progress indicators for operations that take time
- After actions (especially destructive ones), explicitly show success or error feedback
- Visualize live state changes (progress bars, counts, status messages) rather than only final outputs
- At workflow end, show summarized results: what was done, any failures, next steps
- Never leave the user wondering if something is happening

### 5. Forgiving User Input & Prompts
- Use placeholders and default values for inputs (`gum input --placeholder`)
- Allow canceling operations easily (Ctrl+C should always work when safe)
- For filtered lists, allow fuzzy matching and multi-select when relevant
- Accept variations (whitespace, casing, different formats) where possible
- Provide meaningful error messages with actionable guidance
- Validate input clearly and early; show what went wrong immediately

### 6. Minimal Dependency & Simplicity
- Use gum's built-in commands (`style`, `join`, `format`) instead of orchestrating many tools
- Fewer moving parts = easier maintenance and fewer failure points
- Avoid overusing complex layouts unless they add clarity
- A simple vertical flow is often most usable
- Keep prompts short; reduce cognitive load
- Each UI component should do one thing well

### 7. Customizability without Complexity
- Expose style flags (colors, width, borders, etc.) for power users
- Support environment variables for global theming defaults
- Maintain sensible defaults so non-custom users get a polished experience out of the box
- Don't require configuration to be useful
- Allow customization without breaking core functionality
- Document customization options clearly

### 8. Accessible & Inclusive Design
- Use readable color contrasts; avoid color combinations difficult for colorblind users
- Use plain, direct language; avoid jargon and technical abbreviations
- Ensure interactive elements have clear focus states or indicators
- Don't assume terminal supports fancy Unicode or wide emoji
- Test across different terminals (xterm, iTerm2, Windows Terminal, etc.)
- Consider users with limited color support (8-color terminals)
- Provide text alternatives for color-coded information

### 9. Visual Hierarchy & Structure
- Separate status, main content, and prompts visually using spacing and borders
- Use spacing, borders, and alignment to define hierarchy
- Use borders/padding to organize content (header, body, footer)
- Highlight important parts (errors, notifications, warnings)
- Use monospace only for code or structured output; avoid mixing styles that break alignment
- Create clear visual groups for related information

### 10. Progressive Disclosure
- Don't display information the user doesn't need right now
- Let complexity unfold only when needed
- Defaults should be smart; minimize required input
- If only one option is valid, auto-select or skip prompt
- Hide advanced options behind flags or secondary menus
- Show help/hints on demand rather than cluttering the interface

### 11. Stateful Operations & Feedback
- Show task status live: progress of operations as they happen
- Provide summary of actions after operation finishes
- For destructive actions, require explicit confirmation (`gum confirm`)
- Allow cancellation at any point where it makes sense
- Show intermediate states during multi-step processes
- Make it clear what step the user is on in a workflow

### 12. Modular UI Construction
- Build complex flows by combining simple gum commands
- Use `gum choose`, `gum confirm`, `gum filter`, `gum input`, etc. as building blocks
- No ad-hoc ANSI art; use gum components for all UI pieces
- Compose larger interfaces from smaller, focused components
- Each component should be reusable and consistent
- Favor composition over custom implementations

## Gum-Specific Patterns

### Interactive Selection
```bash
# Single selection with header
gum choose --header "Select an option:" "Option 1" "Option 2" "Option 3"

# Multi-select with clear indicators
gum choose --no-limit --header "Select options (space to select):" "Option 1" "Option 2"
```

### User Input
```bash
# Input with placeholder and default
gum input --placeholder "Enter value..." --value "default"

# Secure input for passwords
gum input --password --placeholder "Enter password:"
```

### Confirmation Dialogs
```bash
# Confirm destructive actions
gum confirm "Are you sure you want to delete this file?" && destructive_action

# Confirm with custom prompt styling
gum confirm --prompt.foreground 1 "Warning: This action cannot be undone"
```

### Styled Messages
```bash
# Status message with border
gum style --border double --padding "0 2" --border-foreground 212 "Status: Operation complete"

# Error message with clear styling
gum style --foreground 1 --border double --padding "0 1" "Error: File not found"

# Success message
gum style --foreground 10 --bold "✓ Success"
```

### Progress Indicators
```bash
# Spinner for long operations
gum spin --spinner dot --title "Processing..." -- command_that_takes_time

# Progress with custom spinner
gum spin --spinner line --title "Loading data..." -- long_command
```

## Color Guidelines

### Standard Colors (ANSI 16-color)
- **Success**: Green (`--foreground 10` or `2`)
- **Error**: Red (`--foreground 1`)
- **Warning**: Yellow (`--foreground 3` or `11`)
- **Info**: Blue/Cyan (`--foreground 12` or `4`)
- **Borders**: Subtle, not overwhelming (use `--border-foreground` with lower contrast like `8` or `7`)
- **Highlight**: Bright colors sparingly (e.g., `--foreground 212` for attention)

### Color Accessibility
- Never rely solely on color to convey information
- Use text labels in addition to color coding
- Test with colorblind simulation tools
- Provide high contrast options
- Support terminals with limited color palettes

## Spacing & Layout

### Padding Patterns
- **Tight spacing**: `--padding "0 1"` for inline elements
- **Standard spacing**: `--padding "0 2"` for content blocks
- **Loose spacing**: `--padding "1 2"` for section headers
- **Consistent margins**: Use same padding values throughout

### Layout Principles
- Vertical stacking for most interfaces (easier to read and navigate)
- Horizontal layouts only when space is abundant and relationship is clear
- Clear separation between sections using borders or spacing
- Align related elements for visual harmony

## Error Handling Patterns

### Good Error Messages
```bash
gum style --foreground 1 --border double --padding "0 1" \
  "Error: Configuration file not found
  
  Expected location: ~/.config/app/config.yml
  Fix: Create the file or run 'app init' to generate it"
```

### Bad Error Messages (Avoid)
```bash
# Too technical, no context
echo "ERR: ENOENT"

# No guidance on how to fix
gum style "Error occurred"
```

## Fallback Strategy

When `gum` is not available, provide equivalent functionality:

```bash
if command -v gum &> /dev/null; then
  # Use gum for beautiful UI
  gum choose "Option 1" "Option 2"
else
  # Fallback to basic prompt
  echo "Select option:"
  echo "1) Option 1"
  echo "2) Option 2"
  read -p "Choice: " choice
fi
```

**Fallback Principles:**
- Never fail completely due to missing gum
- Maintain same information architecture
- Use clear, simple text formatting
- Preserve functionality even if visual polish is reduced

## Testing Checklist

Before releasing a TUI, verify:

- [ ] Works in terminal 80x24 (minimum size)
- [ ] Handles missing gum gracefully (fallback works)
- [ ] Color combinations are readable (test with colorblind simulation)
- [ ] Error messages are clear and actionable
- [ ] Long-running operations show progress
- [ ] Destructive actions require confirmation
- [ ] Input validation provides helpful feedback
- [ ] Consistent styling throughout
- [ ] Keyboard shortcuts work (Ctrl+C, Esc, etc.)
- [ ] Tested in at least 2 different terminals

## Common Anti-Patterns (What to Avoid)

### ❌ Don't Do This
- Assume minimum terminal size larger than 80x24
- Use color as the only way to convey important information
- Overwhelm users with too many options at once
- Hide critical information in help text
- Use inconsistent styling across components
- Make destructive actions too easy to trigger
- Provide cryptic error messages
- Skip progress indicators for long operations
- Hard-code terminal-specific features
- Mix ANSI codes with gum (use gum's built-in styling)

### ✅ Do This Instead
- Responsive layouts that adapt to terminal size
- Color + text labels for important information
- Progressive disclosure of options
- Show critical info prominently
- Consistent theme and styling
- Require confirmation for dangerous operations
- Descriptive errors with solutions
- Show progress for any operation >2 seconds
- Use gum's cross-platform components
- Let gum handle all styling and formatting

## References

- [gum GitHub Repository](https://github.com/charmbracelet/gum)
- [gum Documentation](https://github.com/charmbracelet/gum/blob/main/docs/gum.md)
- TUI/CLI UX best practices
- Terminal accessibility guidelines
- ANSI color code standards

## Notes

- These rules should be referenced when implementing any TUI component
- Prefer consistency over cleverness
- When in doubt, choose the simpler, clearer option
- Test in minimal terminals to ensure graceful degradation
- Remember: good UX in terminals requires the same principles as GUI design
- The terminal is a constraint, not an excuse for poor design
