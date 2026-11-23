local tinsert = table.insert
local Enemy = Enemy
local type = type


local LogicalExpressionDelimeters =
{
	[" "] = true,
	["("] = true,
	[")"] = true
}

local LogicalExpressionOperands =
{
	["and"] = true,
	["or"] = true,
	["not"] = true
}


function Enemy.LogicalExpressionIsValidFunctionName (name)
	return name ~= nil and name:match("^[%w%_]+$") and not LogicalExpressionOperands[name]
end


function Enemy.LogicalExpressionParse (str, startPos)

	if (not str) then return nil end

	local len = str:len ()
	local pos = startPos or 1
	local term = ""
	local c

	local res = {}
	local res2


	while (pos <= len)
	do
		c = str:sub (pos, pos)

		if (LogicalExpressionDelimeters[c])
		then
			if (term:len () > 0)
			then
				tinsert (res, term)
				term = ""
			end

			if (c == "(")
			then
				res2, pos = Enemy.LogicalExpressionParse (str, pos + 1)
				tinsert (res, res2)

			elseif (c == ")")
			then
				break
			end
		else
			term = term..c
		end

		pos = pos + 1
	end

	if (term:len () > 0) then tinsert (res, term) end

	return res, pos
end
Enemy._constructorSources = Enemy._constructorSources or {}
Enemy._constructorSources.LogicalExpressionParse = Enemy.LogicalExpressionParse
local stringMeta = getmetatable ("")
Enemy._constructorSources.logicString = {
    library = string, metatable = stringMeta,
    len = string.len, sub = string.sub,
}


function Enemy.LogicalExpressionGetFunctions (expression, result)

	local res = result or {}

	for _, v in ipairs (expression)
	do
		if (not LogicalExpressionOperands[v])
		then
			if (type (v) == "table")
			then
				Enemy.LogicalExpressionGetFunctions (v, res)
			elseif (not res[v])
			then
				res[v] = true
			end
		end
	end

	return res
end


-- Optional context arguments let callers reuse a callback across evaluations.
function Enemy.LogicalExpressionEvaluate (expression, checkFunction, context, value)

	local len = #expression
	local pos = 1
	local v
	local fv
	local op
	local flag = true

	local res = true

	while (pos <= len)
	do
		v = expression[pos]

		if (LogicalExpressionOperands[v])
		then
			if (v == "not")
			then
				flag = not flag
			else
				op = v
			end
		else
			if (type (v) == "table")
			then
                fv = Enemy.LogicalExpressionEvaluate (v, checkFunction, context, value)
			else
                fv = checkFunction (v, context, value)
			end

			if (op)
			then
				if (op == "or")
				then
					res = res or (fv == flag)
				else
					res = res and (fv == flag)
				end
			else
				res = (fv == flag)
			end

			flag = true
		end

		pos = pos + 1
	end

	return res
end
