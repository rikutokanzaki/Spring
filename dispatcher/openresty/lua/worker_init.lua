local http = require("resty.http")
local dict = ngx.shared.sakura_switch

local function fetch_current_mode()
  local c = http.new()
  c:set_timeout(2000)

  local res, err = c:request_uri("http://launcher:5000/current-mode", {
    method = "GET"
  })

  if err then
    ngx.log(ngx.ERR, "[mode-fetch] failed: ", err)
    return nil
  end

  if res.status == 200 then
    local mode = res.body
    return mode
  end

  return nil
end

local function sync_mode()
  local new_mode = fetch_current_mode()
  if new_mode then
    local old_mode = dict:get("mode")
    if old_mode ~= new_mode then
      dict:set("mode", new_mode)
      ngx.log(ngx.INFO, "[mode-sync] ", old_mode, " -> ", new_mode)
    end
  end
end

dict:set("mode", "sakura")
ngx.log(ngx.INFO, "[mode-init] mode=sakura (default)")

local ok, err = ngx.timer.at(0, function()
  local initial_mode = fetch_current_mode()
  if initial_mode then
    dict:set("mode", initial_mode)
    ngx.log(ngx.INFO, "[mode-init] mode=", initial_mode)
  end
end)
if not ok then ngx.log(ngx.ERR, "init timer error: ", err) end

local ok, err = ngx.timer.every(10, sync_mode)
if not ok then ngx.log(ngx.ERR, "sync timer error: ", err) end
