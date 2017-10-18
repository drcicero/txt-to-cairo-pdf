#! /usr/bin/luajit

do -- relative imports
  local pos = arg[0]:reverse():find("/")
  if pos then
    local dir = arg[0]:sub(1, #arg[0]+1-pos)
    package.path = dir .. "?.lua;" .. package.path
  end
end

local argparse = require "argparse"

local lgi = require "lgi"
local c, p, pc = lgi.cairo, lgi.Pango, lgi.PangoCairo
local esc = lgi.GLib.markup_escape_text

--local bold = p.Attribute.weight_new(p.Weight.BOLD)
--local blue = p.Attribute.foreground_new(0xffff, 0xffff, 0xffff)

local function string_rfind(hay, needle)
  return #hay+1-hay:reverse():find(needle)
end

-- trim5 from http://lua-users.org/wiki/StringTrim
local function trim(s)
  return s:match'^%s*(.*%S)' or ''
end

-- https://gist.github.com/yi/01e3ab762838d567e65d
local function tohex(str)
  return str:gsub('.', function (c)
    return string.format('%02X', string.byte(c))
  end)
end

-- pad string with spaces
local function spacepad(str, len)
  return str .. (' '):rep(len - #str)
end

local function startswith(line, prefix)
  return line:sub(1,#prefix)==prefix
end

-- return next paragraph of file
local function parse_paragraph(f)
  local line
  repeat line = f:read("*l") until line ~= ""
  if line == nil then return end

  local par = {}

  -- indented code blocks
  if line:match("^    ") then
    repeat
      table.insert(par, line:sub(5))
      line = f:read("*l")
    until line == nil or not line:match("^    ")
    return "  " .. table.concat(par, "\n  "), "monospace"
  end

  -- fenced code blocks
  local apostart   = line:match("^```")
  local tildestart = line:match("^~~~")
  if apostart or tildestart then
    local ending = "^" .. (apostart and line:match("^`*") or line:match("^~*"))
    line = f:read("*l")
    repeat
      table.insert(par, line)
      line = f:read("*l")
    until line == nil or line:match(ending)
    return "  " .. table.concat(par, "\n  "), "monospace"
  end

  -- text
  if kwarg.multiline ~= "false" then
    repeat
      table.insert(par, line)
      line = f:read("*l")
    until line == "" or line == nil
  else
    table.insert(par, line)
  end

  local list  = #par > 1 and par[1]:match("^%s*(%S)")
  local index = list and par[1]:find("["..list.."]") or 0
  local parlist = {}
  for i=1,#par do
    local continueing = par[i]:sub(index, index) == " "
    list = list and ((continueing and list)
                  or par[i]:match("^%s*(["..list.."])"))
    par[i] = trim(par[i])
    if list then
      if continueing then
        parlist[#parlist] = parlist[#parlist] .. " " .. par[i]
      else
        table.insert(parlist, par[i])
      end
    end
  end

  local result = list and table.concat(parlist, "\n") or table.concat(par, " ")

  local codepoints = {}
  local i = 1
  while i < #result do
    local a,b = result:find("[[](.-)[%]][(](.-)[)]", i)
    if not a then break end
    local name, url = result:sub(a,b):match("[[](.-)[%]][(](.-)[)]")
    result = result:sub(1,a-1) .. name .. result:sub(b+1)
    table.insert(codepoints, {a, a + #name, url})
    i = a + #name
  end

--  local result = (

--    -- bold
--    :gsub("%*%*([^* ][^*]-)%*%*", function(x) return "<b>" .. x .. "</b>" end)
--    :gsub("%*([^* ][^*]-)%*", function(x) return "<i>" .. x .. "</i>" end)

    -- links
--    :gsub("[[](.-)[%]][(](.-)[)]", function(x, y, z)
--      add_link(page, pad,height-y, width-pad,height-y-logical.height/p.SCALE,
--        "/Action << /Subtype /URI /URI (https://www.google.com) >>")
----        "/Page " .. page .. " /View [/XYZ " .. pad .. " " .. (height-y+5) .. " 1]")
--      return x
--    end)

    -- special signs
--    :gsub("%-%-%-", function(x) return "—" end)
--      :gsub("`([^` ][^`]-)[^` ]`", function(x) return "„"..x.."“" end)

--  )

  return result, codepoints, list
end

local function add_page_number(layout, ctx, fonts, page)
  layout.font_description = fonts[1]
  layout.text = "Page " .. page
  local ink, logical = layout:get_extents()
  ctx:move_to(kwarg.size[1]-kwarg.xpad-logical.width/p.SCALE,
              kwarg.size[2]-kwarg.ypad)
  ctx:set_source_rgb(.3,.3,.3) -- foreground color
  ctx:show_layout(layout)
end

--function utf8iter(utf8)
--  local i, j = 1, 1
--  while j < #utf8 do
--    i, j = utf8:find("([%z\1-\127\194-\244][\128-\191]*)", j)
--    coroutine.yield(i, j)
--  end
--end
--utf8iter = coroutine.wrap(utf8iter)

local M = {}

function M.main()  
  local font
  --font = "Bitstream Charter"
  --font = "Caladea"
  font = "Cantarell"
  kwarg  = {
    -- mode
    list_fonts = "false",
    help       = "false",

    -- input
    multiline = "true",

    -- output
    output = "<same as input>.pdf",
    size   = "595x842",
    xpad   = 28*3,
    ypad   = 28*2,
    fonth1   = font.." bold 8",
    fonth2   = font.." bold 8",
    fonth3   = font.." oblique 8",
    font     = font.." 8",
    fontmono = "monospace 7",
  }

  if not argparse(arg, kwarg) then
    return -- error
  end

  if kwarg.list_fonts ~= "false" then
    local fontmap = pc.font_map_get_default()
    local families = {}
    table.foreach( fontmap:list_families(), function(i, font)
      table.insert(families, font:get_name())
    end)
    table.sort(families)
    table.foreach(families, print)
    return
  end

  if kwarg.help ~= "false" or #arg ~= 1 then
    print("USAGE " .. arg[0] .. " INPUT")
    local kwargs = {}
    for k, v in pairs(kwarg) do table.insert(kwargs, {k, v}) end
    table.sort(kwargs, function(x,y) return x[1] < y[1] end)
    for i,v in ipairs(kwargs) do
      print("  --" .. v[1] .. '="' .. tostring(v[2]) .. '"')
    end
    return
  end

  if     kwarg.size == "a4" then kwarg.size = {595, 842}
  elseif kwarg.size == "a5" then kwarg.size = {420, 595}
  else   kwarg.size = { kwarg.size:sub(1, kwarg.size:find("x")-1),
                        kwarg.size:sub(kwarg.size:find("x")+1)} end

  if kwarg.output == "<same as input>.pdf" then
    kwarg.output = arg[1]:sub(1, string_rfind(arg[1], ".")) .. ".pdf"
  end

  local toc = {}
  local links = {}
  do
    local pos = string_rfind(kwarg.font, " ")
    local fontsize = 11 -- tonumber( kwarg.font:sub( pos+1 ) )
    local spacing  = fontsize * .2
    local margin   = spacing + fontsize * .5

    -- init
    local surface = c.PdfSurface("tmp.pdf", kwarg.size[1], kwarg.size[2])
    if "SUCCESS" ~= surface.status then
      print("ERROR", surface.status)
      return os.exit(1)
    end

    local ctx = c.Context(surface)
    local layout = pc.create_layout(ctx)
    layout.width = (kwarg.size[1] - kwarg.xpad*2) * p.SCALE
    layout.height = (kwarg.size[2] - kwarg.ypad*2) * p.SCALE
    layout.ellipsize = "END"
    layout.wrap = "WORD"
    layout.justify = true
    layout.indent = 0
    layout.spacing = spacing * p.SCALE -- line height

    local fonts = {
      p.font_description_from_string(kwarg.font),
      p.font_description_from_string(kwarg.fonth1),
      p.font_description_from_string(kwarg.fonth2),
      p.font_description_from_string(kwarg.fonth3),
      p.font_description_from_string(kwarg.font),
      p.font_description_from_string(kwarg.font),
      mono = p.font_description_from_string(kwarg.fontmono),
    }
    local colors = {
      {0, 0, 0},
      {0, 0, 0},
      {0, 0, 0},
      {0, 0, 0},
      {0, 0, 0},
      {0, 0, 0},
      mono = {0, 0, 0}
    }
    table.foreach(fonts, function(i, x) print(x:to_filename()) end)

    -- add link from srcpage,x,y,x2,y2 to action
    local function add_link (srcpage, x,y, x2,y2, action)
      local x,y,x2,y2 = x-4,y,x2+1,y2
      table.insert(links, "[ /Rect ["..x.." "..y.." "..x2.." "..y2.."]"
        .." /SrcPg "..srcpage.." "..action
        .." /Border [0 0 0.5] /Color [0 0.5 1]"
        .." /Subtype /Link /ANN pdfmark\n")
    end

    local numbering = { -1, 0, 0, 0, 0 }
    local lasttoc = toc
    local lastheading = 2

    local f = io.open(arg[1], "r")
    if not f then print("file not found:", arg[1]) return end

    local par, desc, was_list = parse_paragraph(f)
    local page = 1
    local y = kwarg.ypad

    add_page_number(layout, ctx, fonts, page)
    local heading = 1
    while par do
      layout.indent = was_list and -12*p.SCALE or 0

      -- choose font
      if desc == "monospace" then
        layout.font_description = fonts.mono
        ctx:set_source_rgb(unpack(colors.mono))
        layout.text = par
      else
        if heading == 1 then y=y+ fontsize+spacing*2 end
        if     startswith(par, "##### ") then
          heading = 6
        elseif startswith(par, "#### ") then
          heading = 5
        elseif startswith(par, "### ") then
          heading = 4
        elseif startswith(par, "## ") then
          heading = 3
        elseif startswith(par, "# ") then
          heading = 2
        else
          if heading == 1 then y=y- fontsize-spacing*2 end
          heading = 1
          layout.text = par
        end

        layout.font_description = fonts[heading]
        ctx:set_source_rgb(unpack(colors[heading]))
        if heading ~= 1 then
          numbering[heading-1] = numbering[heading-1] + 1
          for i=heading,5 do
            numbering[i] = 0
          end

          local string = table.concat(numbering, ".", 1, heading-1) .. " "
          if string == "0 " then string = "" end
          layout.text = string .. par:sub(heading+1)
        end
      end

      -- does not fit on this page? -> new page
      local ink, logical = layout:get_extents()
      if y + logical.y/p.SCALE + logical.height/p.SCALE
      >  kwarg.size[2] - kwarg.ypad then
        ctx:show_page()
        y = kwarg.ypad
        page = page + 1
      end

      -- toc for headings
      if heading ~= 1 then
        while lastheading > heading do
          lasttoc = lasttoc.parent
          lastheading = lastheading - 1
        end
        while lastheading < heading do
          lasttoc = lasttoc[#lasttoc]
          lastheading = lastheading + 1
          if lastheading ~= heading then
            table.insert(lasttoc, { parent = lasttoc, text = "", })
          end
        end
        table.insert(lasttoc, {
          parent = lasttoc,
          text = "/Title <" .. tohex(layout.text) .. "> /Page " .. page
            .. " /View [/XYZ " .. kwarg.ypad .. " " .. (kwarg.size[2]-y+5) .. " 1]"
            .. " /OUT pdfmark"
        })
      end

      -- links
      if type(desc) == "table" then
        for _,v in ipairs(desc) do
          local topleft  = layout:index_to_pos(v[1])
          local botright = layout:index_to_pos(v[2])

          for i=topleft.y,botright.y,topleft.height do
            add_link(page,
              i==topleft.y
                and kwarg.xpad+(topleft.x-topleft.width)/p.SCALE
                or kwarg.xpad,
              kwarg.size[2]-y-i/p.SCALE,
              i==botright.y
                and kwarg.xpad+(botright.x-botright.width)/p.SCALE
                or kwarg.size[1]-kwarg.xpad,
              kwarg.size[2]-y-(i+topleft.height)/p.SCALE,
              "/Action << /Subtype /URI /URI ("..v[3]:gsub("[(]", "\\(")..") >>")
          end
        end
      end

      -- write
      do
--        ctx:set_source_rgb(.9,.9,.9)
--        local xpad, ypad = 10, 3
--        ctx:rectangle(kwarg.xpad-xpad, y-ypad,
--          kwarg.size[1]+2*(xpad-kwarg.xpad), logical.height/p.SCALE+2*ypad)
--        local xpad, ypad = 0, 2
--        ctx:rectangle(kwarg.xpad-xpad, y-ypad,
--          kwarg.size[1]+2*(xpad-kwarg.xpad), 1)
--        ctx:fill()

        ctx:move_to(kwarg.xpad, y)
        ctx:show_layout(layout)
      end

      if y == kwarg.ypad then add_page_number(layout, ctx, fonts, page) end
      y = y + logical.height/p.SCALE + margin

      -- next paragraph
      par, desc, was_list = parse_paragraph(f)
    end

    surface:finish()
    f:close()
  end

  do
    -- toc and links
    local pdfmarks = io.open("tmp.txt", "w")
    local function write_toc_rec(toc)
      pdfmarks:write("[ " .. (#toc == 0 and "" or "/Count -" .. #toc .. " ") .. tostring(toc.text).."\n")
      for _,v in ipairs(toc) do write_toc_rec(v) end
    end
    for _,v in ipairs(toc) do write_toc_rec(v) end
    pdfmarks:write("\n")
    for _,v in ipairs(links) do pdfmarks:write(v) end
    pdfmarks:close()
  end

  local exec = "gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile='" ..
    kwarg.output .."' tmp.pdf tmp.txt"
  print(exec)
  os.execute(exec)
  os.remove("tmp.pdf")
  os.remove("tmp.txt")

  print("output written to " .. kwarg.output)
end

M.main()
