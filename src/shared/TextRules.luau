--!strict
-- TextRules: pure sanitising for short player text (guesses, custom prompts).
-- This is NOT a substitute for Roblox text filtering, which the server always applies
-- before showing player text to anyone else.

local TextRules = {}

-- Trims, collapses whitespace, strips control characters and enforces a length cap.
-- Returns the cleaned text, or nil + reason.
function TextRules.sanitize(raw: any, maxLength: number): (string?, string?)
	if type(raw) ~= "string" then
		return nil, "text must be a string"
	end
	if #raw > maxLength * 4 then -- generous byte cap for multi-byte characters
		return nil, "text too long"
	end
	local text = raw:gsub("%c", " ")
	text = text:gsub("%s+", " ")
	text = text:match("^%s*(.-)%s*$") or ""
	if not utf8.len(text) then
		return nil, "invalid text encoding"
	end
	if (utf8.len(text) :: number) > maxLength then
		return nil, "text too long"
	end
	if text == "" then
		return nil, "text is empty"
	end
	return text, nil
end

return TextRules
