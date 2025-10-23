local http = require("resty.http")

local function current_mode()
  local dict = ngx.shared.sakura_switch
  return (dict and dict:get("mode")) or "sakura"
end

local function match_any_in(strs, patterns)
  for _, s in ipairs(strs) do
    if s then
      for _, p in ipairs(patterns) do
        if s:find(p, 1, true) then
          return true
        end
      end
    end
  end
  return false
end

local function proxy(target)
  local mode = current_mode()
  ngx.var.spring_mode    = mode

  return ngx.exec("@" .. target)
end

local function http_post(url)
  local client = http.new()
  client:set_timeout(1500)
  local res, err = client:request_uri(url, { method = "POST" })

  if err then
    return nil, err
  end

  if not res or res.status >= 400 then
    return nil, "bad status: " .. (res and res.status or "nil")
  end
  return res, nil
end

local function with_boot_lock(target, ttl, fn)
  local dict = ngx.shared.sakura_switch
  local key = "bootlock:" .. target

  if dict and dict:add(key, true, ttl or 5) then
    local ok, err = pcall(fn)

    if not ok then
      ngx.log(ngx.ERR, "boot lock fn error: ", err)
    end

    if dict then dict:delete(key) end
  end
end

local upstreams = {
  wordpot   = { name = "wordpot",   port = 80 },
  h0neytr4p = { name = "h0neytr4p", port = 80 },
}

local function wait_upstream_ready(target, total_ms, interval_ms)
  local hp = upstreams[target]
  if not hp then return false end

  local host = hp.host or hp.name
  local port = tonumber(hp.port)

  total_ms = total_ms or 15000
  interval_ms = interval_ms or 200

  ngx.log(ngx.INFO, "[wait] target=", target, " host=", host, " port=", port, " total_ms=", total_ms)
  local deadline = ngx.now() + (total_ms / 1000)
  while ngx.now() < deadline do
    local sock = ngx.socket.tcp()
    sock:settimeout(interval_ms)
    local ok = sock:connect(host, port)
    if ok then
      sock:close()
      ngx.log(ngx.INFO, "[wait] target=", target, " is ready")
      return true
    end
    ngx.sleep(interval_ms / 1000)
  end

  ngx.log(ngx.WARN, "[wait] timeout waiting for target=", target)
  return false
end

local function trigger_and_proxy(target)
  local launcher_port = "5000"
  local launcher_address = "http://launcher:" .. launcher_port .. "/trigger/" .. target
  ngx.log(ngx.INFO, "[trigger+proxy] ", target)

  local mode = current_mode()
  ngx.var.spring_mode    = mode

  with_boot_lock("trg:" .. target, 5, function()
    local client = http.new()
    client:set_timeout(1000)
    local res, err = client:request_uri(launcher_address, { method = "POST" })

    if err then
      ngx.log(ngx.ERR, "[trigger+proxy] error: ", err)
    else
      ngx.log(ngx.INFO, "[trigger+proxy] status=", res and res.status)
    end
  end)

  local ready = wait_upstream_ready(target, 15000, 200)
  if not ready then
    ngx.log(ngx.WARN, "[trigger+proxy] upstream not ready for ", target, " -> fallback to heralding")
    return ngx.exec("@heralding")
  end

  return ngx.exec("@" .. target)
end

local lowint_patterns = {
  "sqlmap", "python-requests", "nmap", "masscan", "nikto", "favicon.ico",
  "c:\\windows\\system32", "/proc/self/environ","cmd.exe", "powershell"
}

local wordpress_patterns = {
  "wp-login.php", "xmlrpc.php", "wp-admin",
  "wp-content", "wp-includes", "wp-json", "wp-config.php",
  "wp-comments-post.php", "wp-cron.php", "wp-"
}

local raw_uri = ngx.var.request_uri or ""
local uri     = raw_uri:lower()
local dec_uri = ngx.unescape_uri(uri)
local ua      = (ngx.var.http_user_agent or ""):lower()
local path    = ngx.var.uri or "/"
local auth    = (ngx.var.http_authorization or ngx.var.http_proxy_authorization or ""):lower()
local has_auth_header = auth:find("basic ", 1, true) or auth:find("digest ", 1, true)

local is_wp   = match_any_in({ uri, dec_uri }, wordpress_patterns)
local is_low  = match_any_in({ uri, dec_uri, ua }, lowint_patterns)
local is_root = (path == "/")

local mode = current_mode()

-- Sakura
if mode == "sakura" then
  if is_wp then
    return trigger_and_proxy("wordpot")
  elseif has_auth_header or is_root or is_low then
    return proxy("heralding")
  else
    return trigger_and_proxy("h0neytr4p")
  end
end

-- Yozakura
if mode == "yozakura" then
  if is_wp then
    return proxy("wordpot")
  elseif has_auth_header or is_root or is_low then
    return proxy("heralding")
  else
    return proxy("h0neytr4p")
  end
end

-- Tsubomi
if mode == "tsubomi" then
  return proxy("h0neytr4p")
end

return proxy("heralding")
