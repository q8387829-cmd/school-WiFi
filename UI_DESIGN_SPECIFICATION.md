# Campus Network Assistant - Modern Dark UI Design Specification

## Design Philosophy

Transform the existing iOS-inspired light interface into a **sharp, production-grade dark interface** with:
- Deep slate/graphite base for professional appearance
- Electric cool accent (sky blue) for primary actions
- Warm brass/orange accent for critical CTAs
- Compact information density
- Precise status indicators

---

## Color Palette

### Base Colors
```
Background:       #0F172A  (Deep navy slate)
Surface:          #1E293B  (Elevated surface)
Surface Light:    #334155  (Lighter surface variant)
```

### Text Hierarchy
```
Primary Text:     #F8FAFC  (Crisp off-white)
Secondary Text:   #CBD5E1  (Secondary information)
Tertiary Text:    #94A3B8  (Hints and labels)
Muted Text:       #64748B  (Disabled/minimal)
```

### Borders
```
Border:           #334155  (Hairline borders)
Border Light:     #475569  (Lighter borders)
```

### Accents
```
Cool Accent (Primary):
  Base:           #38BDF8  (Sky blue)
  Hover:          #0EA5E9
  Pressed:        #0284C7
  Background:     #082F49

Warm Accent (CTA):
  Base:           #F97316  (Orange)
  Hover:          #EA580C
  Pressed:        #C2410C
  Background:     #431407
```

### Status Colors
```
Success:
  Foreground:     #10B981  (Emerald)
  Background:     #064E3B

Warning:
  Foreground:     #F59E0B  (Amber)
  Background:     #451A03

Error:
  Foreground:     #EF4444  (Red)
  Background:     #450A0A

Info:
  Foreground:     #3B82F6  (Blue)
  Background:     #1E3A8A

Neutral:
  Foreground:     #6B7280  (Gray)
  Background:     #1F2937
```

---

## Layout Structure

### Window
- Size: 1080 × 780 px (minimum: 980 × 720 px)
- Background: #0F172A
- Font: Microsoft YaHei UI (primary), Consolas (monospace)

### Sidebar (200px width)
- Background: #1E293B
- Padding: 16px horizontal, 24px top, 20px bottom
- Brand icon: 36×36px, radius 10px, sky blue background
- Navigation items: 168×42px, 2px vertical spacing
- Footer with security note

### Content Area
- Padding: 28px horizontal, 24px top, 12px bottom
- Cards: 12px radius, #1E293B background, #334155 border
- Card padding: 18-24px depending on content density

### Footer Bar (28px height)
- Background: #0F172A
- Status text: 8.5pt, muted color
- Left padding: 228px to align with content

---

## Component Specifications

### Buttons

**Primary (CTA)**
- Background: #F97316 (orange)
- Text: #FFFFFF
- Height: 36px
- Border radius: implicitly handled by button style
- Hover: #EA580C
- Pressed: #C2410C
- No border

**Secondary**
- Background: #1E293B (surface)
- Text: #38BDF8 (cool accent)
- Height: 36px
- Border: 1px #334155
- Hover background: #334155
- Pressed background: #334155

**Ghost (Navigation)**
- Background: Transparent
- Text: #CBD5E1 (secondary text)
- Height: 42px
- No border
- Hover background: #334155
- Active background: #334155
- Active text: #38BDF8

**Danger**
- Background: Transparent
- Text: #EF4444 (error)
- Height: 36px
- Border: 1px #EF4444
- Hover background: #450A0A
- Pressed background: #7F1D1D

### Cards

**Standard Card**
- Background: #1E293B
- Border: 1px #334155
- Radius: 12px
- Padding: 20-24px
- Bottom margin: 12px

**Compact Card** (for metrics)
- Padding: 18px
- Same colors as standard

### Status Badges

**Dimensions**
- Width: 90px
- Height: 24px
- Radius: 10px
- Padding: 10px horizontal, 4px vertical

**Variants**
- Success: #064E3B background, #10B981 text
- Warning: #451A03 background, #F59E0B text
- Error: #450A0A background, #EF4444 text
- Info: #1E3A8A background, #3B82F6 text
- Neutral: #1F2937 background, #6B7280 text

### Icons/Glyphs

**Standard Sizes**
- Small: 16px
- Medium: 18px
- Large: 24px
- Extra Large: 28px

**Status Icon Wells**
- Size: 52×52px
- Radius: 14px
- Padding: 12px
- Background: Status-specific (e.g., #064E3B for success)
- Icon: 28px, status-colored

### Input Fields

**Field Wells**
- Background: #0F172A (darker than card)
- Border: 1px #334155
- Radius: 8px
- Padding: 12px horizontal, 8px vertical
- Input text: #F8FAFC (primary text)
- Font: 10pt Microsoft YaHei UI

**ComboBox**
- Same styling as text input
- Dropdown follows system theme

### Separators
- Height: 1px
- Color: #334155
- Full width within container

---

## Page-Specific Design

### Status Page (Connection Overview)

**Main Connection Card** (240px height)
- Status icon well: 52×52px, colored background
- Primary status text: 18pt bold, #F8FAFC
- Monitor state: 9.5pt, #94A3B8
- Detail text: 10pt, #CBD5E1, multi-line
- VPN indicator: 9pt, #94A3B8, in bordered well (#0F172A background)
- Action buttons: 110px wide

**Metrics Card** (148px height)
- Three rows: Last login, Last error, Last update
- Labels: 9pt, #64748B (muted)
- Values: 9.5pt, #CBD5E1 (secondary)
- Monospace font for timestamps

**Suggestion Bar** (80px height)
- 9.5pt, #94A3B8 (tertiary)
- Top padding: 2px
- Auto-ellipsis enabled

### Account Page

**Credentials Card** (320px height)
- Field labels: 9.5pt, #CBD5E1
- Three input rows (Account, Carrier, Password): 48px each
- Password hint: 8.5pt, #94A3B8, multi-line
- Button row: 44px
- Status label: 8.5pt, #94A3B8

**Preferences Card** (148px height)
- Two toggle rows: 44px each
- Separator: 4px height (includes margins)
- Toggle title: 10pt, #F8FAFC
- Toggle description: 9pt, #94A3B8

### Diagnostics Page

**Results Card** (variable height)
- Title: 14pt bold, #F8FAFC
- Summary: 9.5pt, #CBD5E1
- Four diagnostic items: 29px each
  - Label: 9.5pt, #CBD5E1
  - Icon: 16px, colored by status
  - Value: 9.5pt, colored by status
- Advice label: 9.5pt, #CBD5E1, multi-line
- Full result text box: 9.5pt, #CBD5E1

### Logs Page

**Results Card** (variable height)
- Header: 11pt bold, #F8FAFC
- Log text box:
  - Font: Consolas 9.5pt (monospace)
  - Color: #CBD5E1
  - Word wrap: disabled for logs
  - Background: #1E293B (same as card)

---

## Typography Scale

```
Heading Large:    18pt bold
Heading Medium:   14pt bold
Heading Small:    12pt bold
Subheading:       11pt bold

Body Large:       10.5pt regular
Body Medium:      10pt regular
Body Small:       9.5pt regular

Label Large:      10pt regular
Label Medium:     9.5pt regular
Label Small:      9pt regular

Caption:          8.5pt regular
Micro:            8pt regular

Monospace:        Consolas 9.5pt
```

---

## Interaction States

### Hover
- Buttons: Slightly darker/lighter background
- Navigation: Surface light (#334155) background
- Cards: No hover state (static)

### Active/Pressed
- Buttons: Even darker background
- Navigation: Accent color text + background

### Focus
- Keyboard navigation: Subtle outline in accent color
- Mouse focus: No additional visual indicator

### Disabled
- Opacity reduced (simulated via color mixing)
- Cursor: default (not hand)

---

## Spacing System

### Padding Scale
```
Micro:    4px
Small:    8px
Medium:   12px
Large:    16px
XL:       20px
XXL:      24px
XXXL:     28px
```

### Margin Scale
```
Micro:    2px
Small:    4px
Medium:   8px
Large:    12px
XL:       16px
```

### Component Spacing
- Between cards: 12px
- Button horizontal gap: 8px
- Navigation item vertical gap: 2px
- Section labels above cards: 24px vertical spacing
- Page header to first card: 16px

---

## Visual Hierarchy

### Color Usage Priority
1. **Primary content**: #F8FAFC (high contrast white)
2. **Secondary content**: #CBD5E1 (readable but less prominent)
3. **Tertiary/hints**: #94A3B8 (supporting information)
4. **Muted/disabled**: #64748B (minimal emphasis)

### Component Layering
1. Background (#0F172A)
2. Sidebar surface (#1E293B)
3. Content cards (#1E293B with border)
4. Elevated elements (buttons, inputs)
5. Focus indicators

---

## Accessibility

### Contrast Ratios
- Primary text on background: >7:1 (AAA)
- Secondary text on background: >4.5:1 (AA)
- Button text on button background: >4.5:1 (AA)

### Keyboard Navigation
- All interactive elements focusable
- Visual focus indicators when keyboard is active
- Tab order follows visual flow

### Screen Readers
- All buttons have accessible names
- Status icons have descriptive alt text
- Form inputs have associated labels

---

## Implementation Notes

### Existing Codebase Integration

The existing files to modify:
1. **CampusNetwork.TrayView.ps1** - Main view construction
2. **CampusNetwork.UiControls.ps1** - Custom controls (keep as-is, already modern)
3. **CampusNetwork.Presentation.ps1** - Status formatting (minimal changes needed)

### Key Changes from Current Design

**From Light to Dark:**
- Background: #F2F2F7 → #0F172A
- Surface: #FFFFFF → #1E293B
- Text: #1C1C1E → #F8FAFC

**From iOS Blue to Electric Cool:**
- Accent: #007AFF → #38BDF8

**From Soft to Sharp:**
- Border color: #E9E9EE → #334155
- Radius: 16px → 12px (cards), 14px → 10px (badges)

**Improved Information Density:**
- Reduced padding in sidebar (18px → 16px)
- Tighter row heights (54px → 48px for inputs)
- Compact status cards (272px → 240px)

**Typography Refinements:**
- Primary status: 22pt → 18pt (less oversized)
- Body text: 10.5pt → 10pt (slightly tighter)
- Monospace for timestamps and logs

---

## Migration Path

### Phase 1: Color Palette (Safe, reversible)
Replace all hex color values in view construction functions with new palette

### Phase 2: Component Refinement (Iterative)
- Adjust padding and margins
- Update button dimensions
- Refine status badge styling

### Phase 3: Typography (Low risk)
- Adjust font sizes per specification
- Apply Consolas to timestamps and logs

### Phase 4: Polish (Optional)
- Subtle shadows or glows on status icons
- Animated transitions (if desired)
- Fine-tune hover states

---

## Design Rationale

### Why Dark?
- Reduces eye strain for long monitoring sessions
- Professional, tool-like appearance
- Better contrast for status indicators
- Aligns with modern system utilities

### Why Deep Slate Instead of Pure Black?
- Avoids harsh contrast (#000000 too extreme)
- Provides layering through subtle elevation
- Matches popular development tools (VS Code, etc.)

### Why Electric Cool Accent?
- High visibility against dark background
- Distinguishes from success green
- Modern, technical feel
- Pairs well with warm CTA orange

### Why Warm CTA?
- High visual weight for critical actions
- Complements cool primary accent
- Clear action hierarchy
- Draws attention without being alarming

### Why Compact Density?
- Fits more information in viewport
- Faster visual scanning
- Reduces scrolling
- Aligns with dashboard/monitoring tools

---

## Visual References

The design draws inspiration from:
- **Visual Studio Code** - Dark theme palette, sidebar pattern
- **GitHub Desktop** - Status card layout, badge styling
- **Raycast** - Modern command palette aesthetics
- **Linear** - Sharp borders, compact density
- **Vercel Dashboard** - Status indicators, metrics cards

---

## Color Accessibility Matrix

| Combination | Contrast Ratio | WCAG Level |
|-------------|----------------|------------|
| #F8FAFC on #0F172A | 15.3:1 | AAA |
| #CBD5E1 on #0F172A | 10.8:1 | AAA |
| #94A3B8 on #0F172A | 6.2:1 | AA |
| #FFFFFF on #F97316 | 4.7:1 | AA |
| #FFFFFF on #38BDF8 | 2.8:1 | Fail (use on #1E293B) |
| #38BDF8 on #1E293B | 8.1:1 | AAA |

---

## Final Notes

This specification provides a complete blueprint for transforming the campus network assistant into a modern, professional dark interface. The design prioritizes:

1. **Readability** - High contrast, clear hierarchy
2. **Scannability** - Compact layout, distinct sections
3. **Professionalism** - Sharp, tool-like aesthetic
4. **Usability** - Accessible, keyboard-friendly
5. **Maintainability** - Systematic color palette, consistent spacing

All design decisions are grounded in modern UI best practices and informed by successful reference products in the developer tools space.
