dofile("urlcode.lua")
dofile("table_show.lua")
pcall(require, "luarocks.loader")
htmlparser = require("htmlparser")

local url_count = 0
local tries = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')

local downloaded = {}
local addedtolist = {}

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

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if downloaded[url] == true or addedtolist[url] == true then
    return false

  -- No ads
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

  else
    return true
  end
end


wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  -- Blingees
  if string.match(url, "blingee%.com/blingee/view/") then
    html = read_file(file)
    local root = htmlparser.parse(html)
    -- The way blingee stores images is odd. A lot of the thumbnails
    -- have very similar urls to the actual images.
    -- This selector gets just the main image, which is in the bigbox div.
    local elements = root("div[class='bigbox'] img")
    for _,e in ipairs(elements) do
      newurl = e.attributes["src"]
      table.insert(urls, { url=newurl })
      addedtolist[newurl] = true
      end

  -- Blingee comments
  elseif string.match(url, "blingee%.com/blingee/%d+/comments$") then
    html = read_file(file)
    local root = htmlparser.parse(html)
    local elements = root("div[class='li2center'] div a")
    -- The very last url has the number of total comment pages
    if elements[#elements] then
      local partial_url = elements[#elements].attributes["href"]
      local total_num = string.match(partial_url, "%d+$")
      if total_num then
        for num=2,total_num do
          newurl = url .. "?page=" .. num
          table.insert(urls, { url=newurl })
          addedtolist[newurl] = true
        end
      end
    end

  -- Stamps
  elseif string.match(url, "blingee%.com/stamp/view/") then
    html = read_file(file)
    local root = htmlparser.parse(html)
    local elements = root("div[class='bigbox'] img")
    for _,e in ipairs(elements) do
      newurl = string.match(e.attributes["style"], "http://[^%)]+")
      table.insert(urls, { url=newurl })
      addedtolist[newurl] = true
      end
  end
  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    if string.match(url.url, "https://") then
      local newurl = string.gsub(url.url, "https://", "http://")
      downloaded[newurl] = true
    else
      downloaded[url.url] = true
    end

  elseif status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) then

    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()

    os.execute("sleep 1")

    tries = tries + 1

    if tries >= 15 then
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

    if tries >= 10 then
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
