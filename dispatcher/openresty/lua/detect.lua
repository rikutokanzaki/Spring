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

local high_patterns = {
  -- Scanners / Clients
  "sqlmap","nikto","nmap","masscan","zgrab","whatweb","acunetix","wpscan",
  "nessus","ffuf","gobuster","dirbuster","arachni","owasp zap","zaproxy",
  "python-requests","aiohttp","libwww-perl","curl","wget","go-http-client",
  "okhttp","java/","httpclient","perl","ruby","python",

  -- Sensitive files / Exposures
  "/.git/","/.git/config","/.svn/","/.hg/","/.bzr/","/.DS_Store",
  "/.env","/.htaccess","/.htpasswd","/id_rsa","/id_dsa","/phpinfo.php",
  "/server-status","/web.config","/config.php","/localsettings.php",
  "/crossdomain.xml","/backup","/bak","/adminer.php","/phpmyadmin",

  -- Path Traversal (including encoded)
  "../","..\\","..%2f","%2e%2e%2f","..%5c","%2e%2e%5c","%252e%252e%252f",
  "%2f..%2f","%5c..%5c",

  -- LFI/RFI wrappers
  "file://","php://","phar://","zip://","data://","expect://","jar://",

  -- LFI targets
  "/etc/passwd","/proc/self/environ","/proc/version","/windows/win.ini",
  "c:\\windows\\win.ini","c:\\windows\\system32","/var/log/","/root/.ssh",

  -- SSRF / Cloud metadata
  "169.254.169.254","/latest/meta-data/","metadata.google.internal",
  "localhost","127.0.0.1","0.0.0.0","::1",

  -- SQLi
  " or 1=1"," and 1=1","' or '1'='1","\" or \"1\"=\"1","') or ('1'='1",
  " union select "," order by "," information_schema","load_file(",
  " into outfile","sleep(","benchmark(","xp_cmdshell","@@version",
  "%27%20or%20%271%27%3D%271","or%201%3D1","union%20select",

  -- NoSQLi
  "$ne","$gt","$gte","$lt","$lte","$where","ObjectId(","db.",

  -- Command Injection / RCE
  ";wget",";curl",";id",";uname",";cat",";bash",";sh","&&wget","&&curl",
  "| id","| uname","| nc","| bash","| sh","||","`id`","$(id)","/bin/sh",
  "/bin/bash","/dev/tcp/","bash -i","sh -i","powershell","cmd.exe",
  "certutil -urlcache","bitsadmin","Invoke-WebRequest","Invoke-Expression",

  -- PHP code exec
  "assert(","eval(","system(","exec(","passthru(","shell_exec(",
  "popen(","proc_open(","preg_replace/e",

  -- Java/.NET deserialization
  "rO0AB","java.lang.Runtime","ProcessBuilder","org.apache.commons.collections",
  "ObjectInputStream","ysoserial","System.Diagnostics.ProcessStartInfo",
  "ObjectDataProvider",

  -- Template Injection / SSTI
  "${jndi:","${${","jndi:ldap","jndi:rmi","{{7*7}}","#{7*7}","*{7*7}",
  "${7*7}","T(java.lang.Runtime)",

  -- Shellshock
  "() { :;};","() {","/bin/bash -c",

  -- Struts2 / OGNL
  "method:%23","%23_memberAccess","class.classLoader","redirect:",
  "action:","${%23context",

  -- IoT / Router common paths
  "/cgi-bin/","/boaform/","/HNAP1/","/GponForm/","/uddi/","/hudson/",
  "/manager/html","/luci/","/wlmngr","/tmUnblock.cgi",
}

local wordpress_patterns = {
  "wp-login.php", "xmlrpc.php", "wp-admin",
  "wp-content", "wp-includes", "wp-json", "wp-config.php",
  "wp-comments-post.php", "wp-cron.php", "wp-"
}

for i, v in ipairs(high_patterns) do
  high_patterns[i] = v:lower()
end

for i, v in ipairs(wordpress_patterns) do
  wordpress_patterns[i] = v:lower()
end

local raw_uri = ngx.var.request_uri or ""
local uri     = raw_uri:lower()
local dec_uri = ngx.unescape_uri(uri)
local ua      = (ngx.var.http_user_agent or ""):lower()
local path    = ngx.var.uri or "/"
local auth    = (ngx.var.http_authorization or ngx.var.http_proxy_authorization or ""):lower()
local has_auth_header = auth:find("basic ", 1, true) or auth:find("digest ", 1, true)

local is_wp   = match_any_in({ uri, dec_uri }, wordpress_patterns)
local is_high = match_any_in({ uri, dec_uri, ua }, high_patterns)

local target
if is_wp then
  target = "wordpot"
elseif (not is_wp) and is_high then
  target = "h0neytr4p"
else
  target = "heralding"
end

local mode = current_mode()

-- Sakura
if mode == "sakura" then
  if target == "wordpot" or target == "h0neytr4p" then
    return trigger_and_proxy(target)
  else
    return proxy("heralding")
  end
end

-- Yozakura
if mode == "yozakura" then
  return proxy(target)
end

-- Tsubomi
if mode == "tsubomi" then
  return proxy("h0neytr4p")
end

return proxy("heralding")
