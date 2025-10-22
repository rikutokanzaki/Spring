local dict = ngx.shared.sakura_switch
local modes = { "sakura", "yozakura", "tsubomi" }
local idx = 1
local rotate_interval = 780

dict:set("mode", modes[idx])
ngx.log(ngx.INFO, "[mode-init] mode=", modes[idx])

local function handle_mode_change(new_mode)
  ngx.log(ngx.INFO, "[mode-change] -> ", new_mode)

  local http = require("resty.http")
  local function post(path)
    local c = http.new()
    c:set_timeout(1000)
    local res, err = c:request_uri("http://launcher:5000/" .. path, { method = "POST" })

    if err then
      ngx.log(ngx.ERR, "[launcher] POST /", path, " failed: ", err)

    else
      ngx.log(ngx.INFO, "[launcher] POST /", path, " status=", res and res.status)
    end
  end

  if new_mode == "sakura" then
    post("trigger-infty/heralding")
    post("stop/wordpot")
    post("stop/h0neytr4p")

  elseif new_mode == "yozakura" then
    post("trigger-infty/heralding")
    post("trigger-infty/wordpot")
    post("trigger-infty/h0neytr4p")

  elseif new_mode == "tsubomi" then
    post("stop/wordpot")
    post("stop/h0neytr4p")
    post("trigger-infty/h0neytr4p")
    post("stop/heralding")
  end
end

local function rotate()
  idx = (idx % #modes) + 1
  local new_mode = modes[idx]
  dict:set("mode", new_mode)
  ngx.log(ngx.INFO, "[mode-rotate] -> ", new_mode)

  handle_mode_change(new_mode)
end

local ok, err = ngx.timer.every(rotate_interval, rotate)
if not ok then ngx.log(ngx.ERR, "timer error: ", err) end
