# Tree View — Phase 2 Spec: Direct Structural Editing

## Goal
Replace the indent-text-based edit mode (Phase 1) with direct manipulation of the rendered tree: buffer lines contain only the entry name; branch glyphs and icons are non-editable decoration; structure (parent/child/level/order) is tracked in extmark-backed state and mutated directly by commands (`o`/`O`, `<<`/`>>`, copy/cut/paste), with no visible raw/intermediate text form.

## Core Data Model

- **Buffer line text** = entry name only (plus trailing `/` for directories, as today in `to_raw_lines`, OR drop the slash and rely purely on icon — **open question**, see below).
- **Per-line identity extmark** (namespace `state.identity_ns`), replacing Phase 1's `{orig_path, type}` with:
  ```lua
  state.identity[id] = {
    orig_path = path,   -- nil for newly created entries
    type = "file" | "directory",
    level = N,          -- integer depth, authoritative — no indent parsing
  }
  ```
- **Ordered line list**: line order in the buffer *is* the tree's pre-order traversal. No separate tree object needs to be rebuilt during editing — `level` + buffer order fully encodes parent/child/sibling relationships (a node's parent is the nearest preceding line with `level = node.level - 1`; its children are the contiguous run of following lines with `level > node.level` until one with `level <= node.level`).
- **Decoration extmarks** (namespace `state.decoration_ns`): per-line `virt_text` (or inline virt_text at col 0) holding prefix spacing + branch glyph (`├──`, `└──`, `╞══`, `╘══`) + icon. Rebuilt only for affected ranges (see below), never requires buffer text edits.

## Decoration Recalculation Scope

Any structural mutation (insert, delete, indent, outdent, move, paste) only changes branch glyphs for:
1. The moved/affected line(s) themselves.
2. The *previous* last-sibling-at-that-level, if its "is_last_entry" status flips (its glyph changes from `└──`→`├──` or vice versa) because a new sibling was added/removed after/before it.
3. Nothing else — ancestor prefixes (`│   ` vs `    ` columns) only change if an ancestor's own last-sibling status changes, which cascades but is rare (only when moving/removing the *last* top-level-of-that-ancestor child). Needs a helper: `recompute_decoration_range(from_line, to_line)` that re-derives glyphs purely from the `level` sequence, callable on a narrow slice for perf.

## Commands

### `o` / `O` — new entry
- Determine reference level = current line's level (or for `O`, same; insertion point differs: `o` inserts after current line + its entire subtree if directory... — **decision needed**: does `o` on a directory insert as its first child, or as a sibling after it? Recommend: `o` = sibling after current entry (after its subtree if collapsed/directory), `O` = sibling before current entry. A separate mapping (e.g. `<Tab>o` or just entering a trailing `/` triggers child semantics) could be considered later but out of scope for now.
- Insert blank buffer line, create identity extmark with `level = reference level`, `orig_path = nil` (marks it as pending create, same as Phase 1's "no matching identity" diff rule), run decoration recompute for the narrow range, enter insert mode on the new line for naming.
- Validation on write: empty name after insert mode = abort the add (remove the line) rather than erroring.

### `<<` / `>>` — outdent / indent
Both require a **move algorithm** since line movement is the common case (per our correction), not the exception.

**Indent (`>>`, level N → N+1):**
1. Entry must have a previous sibling at level N (the line immediately preceding its old position at level `<= N`, specifically `== N`). If none exists, indent is a no-op/error (can't indent the first sibling — no parent to attach to).
2. Target position = end of that previous sibling's subtree (i.e., after all its existing descendants).
3. If entry is a directory, its own subtree (contiguous lines with `level > N`) moves with it.
4. Move = buffer line splice: remove the [entry + subtree] block, reinsert at target position, with `level` bumped +1 for the entry (and +1 for every line in its moved subtree, to preserve relative depth).
5. Recompute decoration from the old position's boundary to the new position's boundary (covers both the gap left behind and the insertion point).
6. Move cursor to follow the entry to its new line.

**Outdent (`<<`, level N → N-1):**
1. Entry must have `level >= 1` (can't outdent a root-level entry).
2. Target position = immediately after the entry's current parent's **entire subtree** (i.e., skip past any remaining siblings-and-their-descendants after the entry at the old level).
3. Subtree (if directory) moves with it, all levels -1.
4. Same splice/recompute/cursor-follow as indent.

**Shared move primitive**: implement a single `move_block(start_line, end_line, dest_line, level_delta)` used by both indent/outdent and (later) drag-move, to keep the splice/renumber/decoration-recompute logic in one place.

**Edge cases to test**: indenting/outdenting a collapsed directory (must move the hidden/collapsed subtree too, even though not rendered — need to operate on the full identity/extmark list, not just visible `state.lines`); indent target whose previous sibling is itself collapsed (insert position is still "end of its subtree" even though not visually expanded).

## Copy / Cut / Paste

- **Clipboard** (single implicit slot, upgradeable shape):
  ```lua
  state.clipboard = {
    mode = "copy" | "cut",
    entries = { { name, type, level (relative, 0-based from subtree root) }, ... }, -- pre-order snapshot
  }
  ```
- **Yank range**: from cursor line, include all contiguous following lines with `level > cursor_level` (i.e., the full subtree), plus the cursor line itself. Store levels *relative* to the root entry so paste can re-anchor at any target depth.
- **Cut**: same as copy, plus delete the source lines immediately (identity extmarks removed → diff treats as delete on write, consistent with Phase 1 semantics) and run decoration recompute at the gap.
- **Paste**: insert the stored entries as siblings after the cursor line (at cursor's level), assigning new identity extmarks with `orig_path = nil` (always treated as create — even if cut from elsewhere, since fsops diff doesn't currently support "move with new name/position" as a single op; a cut+paste becomes delete-old + create-new, or optionally a `rename` op if source path is still known — **decision needed**, see Open Questions).
- Recompute decoration for the inserted range + boundary.

## Validation / fsops Changes

- `fsops.validate` no longer parses indentation (`get_indent_level` removed). Instead takes the ordered identity list directly (name + level per line, in buffer order) and only checks: name legality, directory-as-parent constraint (same as today). This removes the "irregular indentation" error class entirely (no longer possible).
- `fsops.diff` unchanged in spirit (extmark-id based comparison), but path resolution now walks `level` directly instead of recovering it from `vim.fn.indent`.

## Open Questions (resolve before/while coding)

1. **Trailing `/` on directory names in buffer text** — keep (matches Phase 1, lets user type it) or drop in favor of relying solely on icon/decoration? Affects `parse_raw_lines`-equivalent and rename detection (type change if user adds/removes trailing `/`).
2. **`o` on a directory**: sibling-after vs first-child? Needs a decision before keymap implementation.
3. **Cut+paste across the tree**: model as `rename` (preserving history/identity) vs `delete`+`create`? Affects whether cut should keep the identity extmark alive (move it, don't delete) and only finalize as delete if never pasted (e.g. on write without paste) — likely cleaner: **cut marks the extmark "pending move" and hides the line; paste re-inserts the same extmark at new position/level, producing a single `rename` op in diff.** This avoids losing file history semantics and reuses the existing extmark=identity model almost for free. Recommend adopting this instead of delete+create.
4. **Multi-level indent/outdent repeat counts** (`3>>`) — in scope for Phase 2 or deferred?
5. **Collapsed-subtree moves** — confirm identity/extmark list is the operand for all moves, never the filtered `state.lines` render list.

## Suggested Build Order
1. Replace raw-text edit mode with extmark-based line/level model (no new commands yet) — i.e., `enter_edit_mode` creates name-only lines + decoration extmarks instead of `to_raw_lines`; `save_edit_mode`/`fsops.validate`/`diff` updated to read `level` from identity instead of parsing indent. This is a drop-in replacement validating the foundation before adding new commands.
2. `o`/`O` insert.
3. `move_block` primitive + `<<`/`>>`.
4. Copy/cut/paste using the "pending move" extmark model.

Let me know if you want to lock in answers to the open questions now, or revisit them when we get to each build step.
