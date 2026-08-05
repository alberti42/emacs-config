--- normalize-headings.lua — shift headings so the shallowest becomes level 1.
---
--- Used by obsidian-to-org.py.  Many notes in the vault start at "###" rather
--- than "#", which converts to "*** Heading" with no parent — valid org, but
--- awkward to fold and to file in an agenda.
---
--- This runs on pandoc's AST rather than on the markdown text on purpose:
--- pandoc has already decided what is a heading, so a "# comment" inside a
--- shell fence cannot be mistaken for one (16 notes here would be), and
--- setext headings, indented code and headings inside blockquotes all behave.
--- Relative nesting is preserved exactly — this is a single integer offset
--- applied uniformly, never a restructuring.

function Pandoc(doc)
  local shallowest = nil

  doc:walk {
    Header = function(h)
      if shallowest == nil or h.level < shallowest then
        shallowest = h.level
      end
    end
  }

  -- No headings, or already starting at level 1: nothing to do.
  if shallowest == nil or shallowest <= 1 then
    return doc
  end

  local shift = shallowest - 1
  return doc:walk {
    Header = function(h)
      h.level = h.level - shift
      return h
    end
  }
end
