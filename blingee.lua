dofile("urlcode.lua")
dofile("table_show.lua")
pcall(require, "luarocks.loader")
htmlparser = require("htmlparser")

local url_count = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')

local downloaded = {}

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

parse_html = function(file, selector)
  local html = read_file(file)
  local root = htmlparser.parse(html)
  return root(selector)
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]

  -- Skip avatars/thumbnails on group frontpage, topics, and managers.
  -- We do get the avatars from the memberlist as they are fullsize.
  if string.match(url, "%.gif[%?%d]*$") and
     (string.match(parent["url"], "blingee%.com/group/%d+$") or
      string.match(parent["url"], "blingee%.com/group/%d+-") or
      string.match(parent["url"], "blingee%.com/group/%d+/managers") or
      string.match(parent["url"], "blingee%.com/group/%d+/topic")) then
    return false

  -- No ads or trackers
  elseif string.match(url, "https?://partner%.googleadservices%.com") or
    string.match(url, "http://.+%.scorecardresearch%.com") or
    string.match(url, "http://.+%.quantserve%.com") then
    return false

  -- No javascripts or stylesheets (they're already saved.)
  elseif string.match(url, "http://blingee%.com/javascripts/") or
    string.match(url, "http://blingee%.com/stylesheets/") or
    string.match(url, "http://blingee%.com/images/web_ui/") or 
    string.match(url, "http://blingee%.com/favicon%.gif") or
    string.match(url, "http://blingee%.com/images/spaceball%.gif") then
    return false

  -- Site stuff that is already saved elsewhere,
  elseif string.match(url, "page=1$") or
         string.match(url, "[%?&]list_type=409[78]") or
         string.match(url, "blingee%.com/group/%d+/member/") or
         string.match(url, "blingee%.com/group/%d+/blingees") or
         string.match(url, "blingee%.com/groups$") or
         string.match(url, "%?offset=%d+") then
    return false

  -- ... requires a login, or makes wget go nuts.
  elseif string.match(url, "/choose_blingee$") or
         string.match(url, "/join$") or
         string.match(url, "/login$") or
         string.match(url, "/add_topic") or
         string.match(url, "blingee%.com/group/tags/") or
         string.match(url, "[%?&]lang=") then
    return false

  else
    downloaded[url] = verdict
    return verdict
  end
end


wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  check = function(newurl)
    if downloaded[newurl] ~= true then
      table.insert(urls, { url=newurl })
      downloaded[newurl] = true
    end
  end

  -- Blingees
  if string.match(url, "blingee%.com/blingee/view/") then
    -- The way Blingee stores images is odd. A lot of the thumbnails
    -- have very similar urls to the actual image.
    -- This selector gets just the main image, which is in the bigbox div.
    local elements = parse_html(file, "div[class='bigbox'] img")
    for _,e in ipairs(elements) do
      newurl = e.attributes["src"]
      check(newurl)
    end

  -- Blingee comments
  elseif string.match(url, "blingee%.com/blingee/%d+/comments$") then
    local elements = parse_html(file, "div[class='li2center'] div a")
    -- The very last url has the total number of comment pages
    if elements[#elements] then
      local partial_url = elements[#elements].attributes["href"]
      local total_num = string.match(partial_url, "%d+$")
      if total_num then
        for num=2,total_num do
          newurl = url .. "?page=" .. num
          check(newurl)
        end
      end
    end

  -- Stamps
  elseif string.match(url, "blingee%.com/stamp/view/") then
    local elements = parse_html(file, "div[class='bigbox'] img")
    for _,e in ipairs(elements) do
      newurl = string.match(e.attributes["style"], "http://[^%)]+")
      check(newurl)
    end

  -- Group urls are found via the --recursive wget flag,
  -- but we do have to add the group logo.
  elseif string.match(url, "blingee%.com/group/%d+$") then
    local elements = parse_html(file, "div[class='bigbox'] img")
    for _,e in ipairs(elements) do
      newurl = e.attributes["src"]
      check(newurl)
    end
  end
  return urls
end


wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  local status_code = http_stat["statcode"]
  local sleep_time = 15
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if status_code >= 500 or (status_code >= 400 and status_code ~= 404) then
    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()

    -- Note that wget has its own linear backoff to this time as well
    os.execute("sleep " .. sleep_time)
    return wget.actions.CONTINUE
  else
    -- We're okay; sleep a bit (if we have to) and continue
    local sleep_time = 0 -- 1.0 * (math.random(75, 125) / 100.0)

    if sleep_time > 0.1 then
      os.execute("sleep " .. sleep_time)
    end

    tries = 0
    return wget.actions.NOTHING
  end
end
