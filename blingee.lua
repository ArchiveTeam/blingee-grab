dofile("urlcode.lua")
dofile("table_show.lua")
require 'io'

local url_count = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')

local downloaded = {}
local todo = {}

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

line_num = function(linenum, filename)
  local num = 0
  for line in io.lines(filename) do
    num = num + 1
    if num == linenum then
      return line
    end
  end
end

trim = function(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

parse_html = function(file, selector, index)
  index = index or ""
  local handle = io.popen("python ./parse_html.py "..file.." "..selector.." "..index)
  local html = handle:read("*a")
  handle:close()
  return html
end

is_resource = function(url)
  local patterns = {"%.gif[%?%d]*$",
                    "%.png[%?%d]*$",
                    "%.jpe?g[%?%d]*$",
                    "%.css[%?%d]*$",
                    "%.js[%?%d]*$",
                    "%.swf[%?%d]*$"}
  for _,pattern in ipairs(patterns) do
    if string.match(url, pattern) then
      return true
    end
  end
  return false
end

check = function(url, parent, verdict)
  if downloaded[url] == true or todo[url] == true then
    return false

  -- url should actually be a url.
  elseif not string.match(url, "^https?://") then
    return false

  -- Ignore blingee language options
  elseif string.match(url, "https?://de%.blingee%.com/") or
         string.match(url, "https?://es%.blingee%.com/") or
         string.match(url, "https?://fr%.blingee%.com/") or
         string.match(url, "https?://it%.blingee%.com/") or
         string.match(url, "https?://nl%.blingee%.com/") or
         string.match(url, "https?://pt%.blingee%.com/") or
         string.match(url, "https?://ru%.blingee%.com/") or
         string.match(url, "https?://ja%.blingee%.com/") or
         string.match(url, "https?://ko%.blingee%.com/") then
    return false

  -- Groups: Skip avatars/thumbnails on group frontpage, topics, and managers.
  elseif parent and is_resource(url) and
     (string.match(parent["url"], "blingee%.com/group/%d+$") or
      string.match(parent["url"], "blingee%.com/group/%d+-") or
      string.match(parent["url"], "blingee%.com/group/%d+/managers") or
      string.match(parent["url"], "blingee%.com/group/%d+/topic") or
      string.match(parent["url"], "blingee%.com/group/%d+/member")) then
    return false

  -- Groups: Except for resources, only grab urls that contain item_type.
  elseif parent and (item_type == "group" and
                     string.match(parent["url"], "/group/") and
                     not is_resource(url) and
                     not string.match(url, "blingee%.com/group/")) then
    return false

  -- Groups: Skip other groups.
  elseif item_type == "group" and
         string.match(url, "blingee%.com/group/%d+[^%d]*") and
         not string.match(url, "blingee%.com/group/"..item_value.."/") then
    return false

  -- No need to redo badges as we're already grabbing them.
  elseif string.match(url, "blingee%.com/images/badges/") and item_type ~= "badge" then
    return false

  -- No ads or trackers
  elseif string.match(url, "https?://partner%.googleadservices%.com") or
    string.match(url, "http://.+%.scorecardresearch%.com") or
    string.match(url, "http://.+%.quantserve%.com") then
    return false

  -- Ignore static stuff that has no timestamps.
  elseif string.match(url, "http://blingee%.com/images/web_ui/[^%?]+$") or
    string.match(url, "http://blingee%.com/favicon%.gif") or
    string.match(url, "http://blingee%.com/images/spaceball%.gif") then
    return false

  -- Site stuff that is already saved elsewhere,
  elseif string.match(url, "^https?://blingee%.com/$") or
         string.match(url, "blingee%.com/about") or
         string.match(url, "blingee%.com/partner") or
         string.match(url, "blingee%.com/group/%d+/.+page=1$") or
         string.match(url, "[%?&]list_type=409[78]") or
         string.match(url, "blingee%.com/group/%d+/member/") or
         string.match(url, "blingee%.com/group/%d+/blingees") or
         string.match(url, "blingee%.com/groups$") or
         (string.match(url, "host%d+-static%.blingee%.com") and item_type == "group") or
         string.match(url, "%?offset=%d+") then
    return false

  -- ... requires a login, or makes wget go nuts.
  elseif string.match(url, "blingee%.com/images/web_ui/default_deleted_avatar%.gif%?1341491498") or
         string.match(url, "blingee%.com/images/web_ui/default_avatar%.gif%?1341491498") or
         string.match(url, "/choose_blingee$") or
         string.match(url, "/choose_spotlight$") or
         string.match(url, "/upload_base$") or
         string.match(url, "/join$") or
         string.match(url, "/signup$") or
         string.match(url, "/login$") or
         string.match(url, "%?page=%d+%?page=%d+") or
         string.match(url, "blingee%.com/gift/") or
         string.match(url, "blingee%.com/user_circle/join") or
         string.match(url, "blingee%.com/user_circle/block_user") or
         string.match(url, "blingee%.com/profile/.+/spotlight") or
         string.match(url, "blingee%.com/profile/.+/postcards") or
         string.match(url, "blingee%.com/profile/.+/challenges") or
         string.match(url, "blingee%.com/goodie_bag") or
         string.match(url, "/add_topic") or
         string.match(url, "/add_post") or
         string.match(url, "blingee%.com/group/tags/") or
         string.match(url, "blingee%.com/blingee/tags/") or
         string.match(url, "blingee%.com/pictures/") or
         string.match(url, "[%?&]lang=") then
    return false
  end
  return verdict or true
end

-- Ignore urls that are already saved.
for url in string.gmatch(read_file("ignorelist.txt"), "[^\n]+") do
  downloaded[url] = true
end


wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  passed = check(url, parent, verdict)
  if passed then
    todo[url] = true
  end
  return passed
end


wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = read_file(file)

  if downloaded[url] ~= true then
    downloaded[url] = true
  end

  -- Check url and, if valid and not downloaded, insert into urls.
  insert = function(newurl)
      if newurl ~= nil and check(newurl) and todo[newurl] ~= true
         and downloaded[newurl] ~= true then
        table.insert(urls, { url=newurl })
        todo[newurl] = true
      end
  end

  -- Check url for possible matches.
  -- If matched, returns newurl. Else, nil
  match_url = function(newurl)
    -- Get extra, possibly new css/js.
    if string.match(newurl, "%.css") or string.match(newurl, "%.js") then
      return newurl
    -- I don't think there are any swfs other than for stamps,
    -- but just in case
    elseif string.match(newurl, "%.swf") then
      return newurl
    else
      return nil
    end
  end

  -- Find various common links.
  if not is_resource(url) then
    for newurl in string.gmatch(html, '"(https?://[^"]+)"') do
      insert(match_url(newurl))
    end

    for newurl in string.gmatch(html, '("/[^"]+)"') do
      if string.match(newurl, '"//') then
        insert(match_url(string.gsub(newurl, '"//', 'http://')))
      elseif not string.match(newurl, '"//') then
        insert(match_url(string.match(url, "(https?://[^/]+)/")..string.match(newurl, '"(/.+)')))
      end
    end

    for newurl in string.gmatch(html, "('/[^']+)'") do
      if string.match(newurl, "'//") then
        insert(match_url(string.gsub(newurl, "'//", "http://")))
      elseif not string.match(newurl, "'//") then
        insert(match_url(string.match(url, "(https?://[^/]+)/")..string.match(newurl, "'(/.+)")))
      end
    end
  end

  -- Profiles
  -- First, all the people in their "circle"
  if string.match(url, "blingee%.com/profile/.+/circle") then
    local partial_url = trim(parse_html(file, [[//div[@class=\"pagination\"]/a/@href]], -1))
    if partial_url then
      local total_num = string.match(partial_url, "%d+$")
      if total_num and string.match(partial_url, "page=%d+") then
        for num=2,total_num do
          newurl = url .. "?page=" .. num
          insert(newurl)
        end
      end
    end
  -- And comments
  elseif string.match(url, "blingee%.com/profile/.+/comments") then
    local partial_url = trim(parse_html(file, [[//div[@class=\"li2center\"]//div//a/@href]], -1))
    if partial_url then
      local total_num = string.match(partial_url, "%d+$")
      if total_num and string.match(partial_url, "page=%d+") then
        for num=2,total_num do
          newurl = url .. "?page=" .. num
          insert(newurl)
        end
      end
    end
  -- Get the avatar
  elseif string.match(url, "blingee%.com/profile/") then
    local newurl = trim(parse_html(file, [[//div[@class=\'bigbox\']//img/@src]], 0))
    insert(newurl)

  -- Blingees
  elseif string.match(url, "blingee%.com/blingee/view/%d+$") then
    -- The way Blingee stores images is odd. A lot of the thumbnails
    -- have very similar urls to the actual image.
    -- This selector gets just the main image, which is in the bigbox div.
    local newurl = trim(parse_html(file, [[//div[@class=\'bigbox\']//img/@src]], 0))
    local canonical = "http://blingee.com"..trim(parse_html(file, [[//link[@rel=\'canonical\']/@href]], 0))
    insert(newurl)
    insert(canonical)

  -- Blingee comments
  elseif string.match(url, "blingee%.com/blingee/%d+/comments$") then
    -- The very last url has the total number of comment pages
    local partial_url = trim(parse_html(file, [[//div[@class=\'li2center\']//div//a/@href]], -1))
    local total_num = string.match(partial_url, "%d+$")
    if total_num and string.match(partial_url, "page=%d+") then
      for num=2,total_num do
        newurl = url .. "?page=" .. num
        insert(newurl)
      end
    end

  -- Stamps
  elseif string.match(url, "blingee%.com/stamp/view/") then
    local partial_url = trim(parse_html(file, [[//div[@class=\'bigbox\']//img/@style]], 0))
    newurl = string.match(partial_url, "http?://[^%)]+")
    insert(newurl)

  -- Group urls are found via the --recursive wget flag,
  -- but we do have to add the group logo.
  elseif string.match(url, "blingee%.com/group/%d+$") then
    newurl = trim(parse_html(file, [[//div[@class=\'bigbox\']//img/@src]], 0))
    insert(newurl)

  -- Competition rankings
  elseif string.match(url, "blingee%.com/competition/rankings/%d+$") then
    local partial_url = trim(parse_html(file, [[//div[@class=\'content_section\']//a/@href]], -1))
    local total_num = string.match(partial_url, "%d+$")
    if total_num and string.match(partial_url, "page/%d+") then
      for num=2,total_num do
        newurl = url .. "/page/" .. num
        insert(newurl)
      end
    end

  -- Challenge rankings
  elseif string.match(url, "blingee%.com/challenge/rankings/%d+$") then
    local partial_url = trim(parse_html(file, [[//div[@class=\'content_section\']//a/@href]], -1))
    local total_num = string.match(partial_url, "%d+$")
    if total_num and string.match(partial_url, "page=%d+") then
      for num=2,total_num do
        newurl = url .. "?page=" .. num
        insert(newurl)
      end
    end

  -- Badges
  elseif string.match(url, "blingee%.com/badge/") then
    -- Get the actual badge
    if string.match(url, "/view/%d+$") then
      local description = trim(parse_html(file, [[//div[@class=\'description\']//p//a//img/@src]], 0))
      if description then
        insert("http:" .. description)
      end
    -- Winner list
    elseif string.match(url, "/winner_list/%d+$") then
      local partial_url = trim(parse_html(file, [[//div[@class=\'pagination\']//a/@href]], -1))
      local total_num = string.match(partial_url, "%d+$")
      if total_num and string.match(partial_url, "page=%d+") then
        for num=2,total_num do
          newurl = url .. "?page=" .. num
          insert(newurl)
        end
      end
    end
  end
  return urls
end


wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  local status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  -- Save the url shortener, but stop at the second redirect.
  if status_code == 302 or status_code == 301 and
     item_type == "blingee" and string.match(url.url, "^https?://blingee%.com/b/.+") then
    return wget.actions.EXIT
  end

  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404 and status_code ~= 403) then

    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()

    os.execute("sleep 10")

    tries = tries + 1

    if tries >= 6 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    else
      return wget.actions.CONTINUE
    end
  elseif status_code == 0 then

    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()

    os.execute("sleep 10")
    
    tries = tries + 1

    if tries >= 3 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end
