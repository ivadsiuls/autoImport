-- https://github.com/luau-lang/luau/blob/master/Ast/src/Lexer.cpp

const Types = require("./Types")

const function isNewline(ch: string)
	return ch == "\n"
end

const function isSpace(ch: string)
	return ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == "\v" or ch == "\f"
end

const function makeRange(start: Types.Position, finish: Types.Position): Types.Range
	return {
		start = start,
		["end"] = finish,
	}
end

const function parseScript(source: string): {
	comments: { Types.Comment },
	strings: { Types.String },
}
	local length = #source
	local offset = 1

	local line = 1
	local lineOffset = 1

	local isHeaderBlock = true
	local braceStack: { string } = {} -- "normal", "interp"

	const function position(): Types.Position
		return {
			line = line,
			character = offset - lineOffset + 1,
		}
	end

	const function peekCh()
		return string.sub(source, offset, offset)
	end

	local function consume()
		if isNewline(peekCh()) then
			line += 1
			lineOffset = offset + 1 -- as if we already incremented offset
		end
		offset += 1
	end

	local function skipLongSeparator()
		const start = peekCh()
		local count = 0
		offset += 1 -- always [ or ]
		while peekCh() == "=" do
			count += 1
			offset += 1
		end
		return if start == peekCh() then count else -count - 1
	end

	local function readLongComment(start: Types.Position, sep: number): Types.Comment
		consume() -- second [
		local startOffset = offset

		while offset <= length do
			if peekCh() == "]" then
				if skipLongSeparator() == sep then
					const finish = position()
					consume() -- second ]
					return {
						kind = "long",
						range = makeRange(start, finish), -- includes final ]
						text = string.sub(source, startOffset, offset - sep - 3),
						header = false,
					}
				end
			else
				consume()
			end
		end

		return { -- broken/unfinished comment
			kind = "long",
			range = makeRange(start, position()),
			text = string.sub(source, startOffset, offset),
			header = false,
		}
	end

	local function readComment(): Types.Comment
		const start = position()
		offset += 2 -- two opening dashes

		local startOffset = offset

		if peekCh() == "[" then
			const sep = skipLongSeparator()
			if sep >= 0 then
				return readLongComment(start, sep)
			end
		end

		while offset < length and not isNewline(peekCh()) do
			offset += 1
		end

		return {
			kind = "simple",
			range = makeRange(start, position()), -- includes newline/eof
			text = string.sub(source, startOffset, offset - 1),
			header = false,
		}
	end

	local function readLongString(start: Types.Position, sep: number): Types.String
		consume() -- second [
		local startOffset = offset
		while offset <= length do
			if peekCh() == "]" then
				if skipLongSeparator() == sep then
					const finish = position()
					consume() -- second ]
					return {
						kind = "long",
						range = makeRange(start, finish), -- includes final ]
						text = string.sub(source, startOffset, offset - sep - 3),
					}
				end
			else
				consume()
			end
		end

		return { -- broken/unfinished string
			kind = "long",
			range = makeRange(start, position()),
			text = string.sub(source, startOffset, offset),
		}
	end

	local function skipBackslashInString()
		consume()
		const escch = peekCh()
		if escch == "z" then
			consume()
			while isSpace(peekCh()) do
				consume()
			end
		elseif escch ~= "" then
			consume()
		end
	end

	local function readQuotedString(): Types.String
		const start = position()
		const delim = peekCh()
		consume() -- delim

		local startOffset = offset
		while peekCh() ~= delim do
			const ch = peekCh()
			if ch == "" or ch == "\n" then
				return {
					kind = "quoted",
					range = makeRange(start, position()), -- includes newline/eof
					text = string.sub(source, startOffset, offset - 1),
				}
			elseif ch == "\\" then
				skipBackslashInString()
			else
				consume()
			end
		end

		const finish = position()
		consume() -- delim

		return {
			kind = "quoted",
			range = makeRange(start, finish), -- includes closing delim
			text = string.sub(source, startOffset, offset - 2),
		}
	end

	local function readInterpSection(start: Types.Position, startOffset: number): Types.String
		while peekCh() ~= "`" do
			const ch = peekCh()
			if ch == "" or ch == "\n" then
				return { -- broken interp
					kind = "interp",
					range = makeRange(start, position()),
					text = string.sub(source, startOffset, offset - 1),
				}
			elseif ch == "\\" then
				if string.sub(source, offset + 1, offset + 2) == "u{" then
					offset += 3 -- \u{
				else
					skipBackslashInString()
				end
			elseif ch == "{" then
				table.insert(braceStack, "interp")
				const finish = position()
				consume()
				if peekCh() == "{" then
					const doubleBraceFinish = position()
					consume()
					return {
						kind = "interp",
						range = makeRange(start, doubleBraceFinish),
						text = "", -- broken double brace
					}
				end
				return {
					kind = "interp", -- section
					range = makeRange(start, finish),
					text = string.sub(source, startOffset, offset - 1),
				}
			else
				consume()
			end
		end

		const finish = position()
		consume() -- closing `

		return {
			kind = "interp",
			range = makeRange(start, finish),
			text = string.sub(source, startOffset, offset - 1),
		}
	end

	local function readInterpBegin(): Types.String
		const start = position()
		const startOffset = offset
		consume()
		return readInterpSection(start, startOffset)
	end

	const comments = {}
	const strings = {}

	while true do
		while isSpace(peekCh()) do
			consume()
		end
		if offset > length then
			break
		end

		if string.sub(source, offset, offset + 1) == "--" then
			const comment = readComment()
			comment.header = isHeaderBlock
			table.insert(comments, comment)
			continue
		end

		-- non-comment lexeme
		isHeaderBlock = false

		if peekCh() == '"' or peekCh() == "'" then
			table.insert(strings, readQuotedString())
		elseif peekCh() == "[" then
			const start = position()
			const sep = skipLongSeparator()
			if sep >= 0 then
				table.insert(strings, readLongString(start, sep))
			elseif sep < -1 then
				const finish = position()
				table.insert(strings, { -- e.g. a lone [==
					kind = "long",
					range = makeRange(start, {
						line = finish.line,
						character = finish.character - 1,
					}),
					text = "",
				})
				consume()
			else
				consume()
			end
		elseif peekCh() == "`" then
			table.insert(strings, readInterpBegin())
		elseif peekCh() == "{" then
			consume()
			if #braceStack > 0 then
				table.insert(braceStack, "normal")
			end
		elseif peekCh() == "}" then
			const start = position()
			const startOffset = offset
			consume()
			local braceStackTop = table.remove(braceStack)
			if braceStackTop == "interp" then
				table.insert(strings, readInterpSection(start, startOffset))
			end
		else
			consume()
		end
	end

	return {
		comments = comments,
		strings = strings,
	}
end

return parseScript
