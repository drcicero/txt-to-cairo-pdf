local function parse_args(args, defaults)
  local i = 0
  local ok = true

  while i < #args+1 do
    if args[i]:sub(1, 2) == "--" then
      local arg = table.remove(args, i)
      local pos = arg:find("=") or #arg+1
      local key, value = arg:sub(3, pos-1), arg:sub(pos+1)
      if defaults[key] == nil then
        print("invalid argument:", key .. " = " .. value)
        ok = false
      end
      defaults[key] = value
    else
      i = i+1
    end
  end

  return ok
end

return parse_args

