#!/bin/sh
set -e

global_code_failure=50
global_code_param_missing=11
global_code_param_invalid=12
global_code_no_access=41
global_code_not_found=44

print_message(){
  echo "$1"
}

command_exists() {
  # command -v $1 > /dev/null 2>&1
  command -v "$@" > /dev/null 2>&1
  # return $?
}

docker_running() {
  # 检测 docker 是否已安装
  if ! command_exists docker; then
    return $global_code_failure
  fi
  docker info > /dev/null 2>&1
  return $?
}

docker_start() {
  sudo systemctl restart docker
  if [ "$?" = "0" ]; then
    print_message "docker 启动成功"
    return 0
  else
    print_message "docker 启动失败：sudo systemctl restart docker"
    return $global_code_failure
  fi
}

# 检查镜像是否存在
nginx_image_exists() {
  if docker image inspect "$global_nginx_full_image" >/dev/null 2>&1; then
    return 0
  else
    return $global_code_not_found
  fi
}

nginx_image_pull() {
  print_message "正在拉取镜像：$global_nginx_full_image"
  docker pull "$global_nginx_full_image"
  return $?
}

nginx_container_create(){
  print_message "创建容器：docker run -d --name $global_nginx_container_name --restart unless-stopped --network host -v $global_nginx_home_path/html:/usr/share/nginx/html -v $global_nginx_home_path/conf:/etc/nginx -v $global_nginx_home_path/certbot:/etc/letsencrypt $global_nginx_full_image"
  # -e TZ=Asia/Shanghai
  if [ -z "$global_nginx_time_zone" ]; then
    docker run -d --name "$global_nginx_container_name" --restart unless-stopped --network host -v "$global_nginx_home_path"/html:/usr/share/nginx/html -v "$global_nginx_home_path"/conf:/etc/nginx -v "$global_nginx_home_path"/certbot:/etc/letsencrypt "$global_nginx_full_image"
  else
    docker run -d --name "$global_nginx_container_name" --restart unless-stopped --network host -e TZ="$global_nginx_time_zone" -v "$global_nginx_home_path"/html:/usr/share/nginx/html -v "$global_nginx_home_path"/conf:/etc/nginx -v "$global_nginx_home_path"/certbot:/etc/letsencrypt "$global_nginx_full_image"
  fi
}

nginx_config_default() {
  # 生成默认配置（映射到容器外，即宿主机目录）
  print_message "生成默认配置（映射到容器外，即宿主机目录：${global_nginx_home_path}）"
  docker run -it --rm -v "${global_nginx_home_path}"/conf:/opt/nginx/originals/tmp "$global_nginx_full_image" sh -c "cp -rp /etc/nginx/* /opt/nginx/originals/tmp"
  cp -rp "${global_nginx_home_path}"/conf/conf.d "${global_nginx_home_path}"/conf/sites
  rm -rf "${global_nginx_home_path}"/conf/sites/*
  if [ -f "${global_nginx_home_path}/conf/conf.d/default.conf" ]; then
    cp -p "${global_nginx_home_path}"/conf/conf.d/default.conf "${global_nginx_home_path}"/conf/sites/default.conf.bak
  fi
  cp -p "${global_nginx_home_path}"/conf/nginx.conf "${global_nginx_home_path}"/conf/nginx.conf.original.bak
  #if [ -f "${global_work_template_path}/nginx-main.conf" ]; then
  #  #cat /dev/null > "${global_nginx_home_path}"/conf/nginx.conf
  #  cat "${global_work_template_path}"/nginx-main.conf > "${global_nginx_home_path}"/conf/nginx.conf
  #fi
  echo "hello world, nginx !!!" > "${global_nginx_home_path}"/html/test.txt
}

nginx_config_main(){
  print_message "Nginx站点目录：${global_nginx_home_path}/html"
  print_message "Nginx配置目录：${global_nginx_home_path}/conf"
  print_message "Nginx默认SSL证书目录：${global_nginx_home_path}/conf/certs"
  print_message "Nginx主配置文件：${global_nginx_home_path}/conf/nginx.conf"

  cat << EOF > "${global_nginx_home_path}"/conf/nginx.conf
#========global====================================================================================
#user                                nobody nobody;
worker_processes                     auto;
worker_cpu_affinity                  auto;
worker_rlimit_nofile                 65535;

# [ debug | info | notice | warn | error | crit ]
error_log                            /var/log/nginx/error.log notice;
pid                                  /var/run/nginx.pid;

#========events====================================================================================
events {
    use                              epoll;
    # count per work processer
    worker_connections               65535;
    #accept_mutex                    on;
    multi_accept                     on;
}

http {
    include                          mime.types;
    default_type                     application/octet-stream;

    # zoro copy setting
    sendfile                         on;
    sendfile_max_chunk               128k;
    #send_lowat                      12000;
    tcp_nopush                       on;
    #tcp_nodelay                     on;

    # keepalive setting
    keepalive_timeout                30s;
    keepalive_requests               100;

    # client setting
    # buffers setting, get memery pagesize command: [getconf PAGESIZE]
    client_header_buffer_size        4k;
    large_client_header_buffers      4 8k;
    client_body_buffer_size          64k;
    client_max_body_size             10m;
    client_body_in_single_buffer     on;
    #client_body_temp_path           /path/to/tmp/client_body_temp;

    # proxy setting
    proxy_buffering                  on;
    proxy_buffer_size                4k;
    proxy_buffers                    64 8k;
    #proxy_temp_path                 /path/to/tmp/proxy_temp;
    #proxy_max_temp_file_size        512k;
    #proxy_temp_file_write_size      64k;
    #proxy_cache_path                /path/to/tmp/proxy_cache levels=1:2 keys_zone=cache_one:512m inactive=1d max_size=2g;

    # timeout setting
    client_header_timeout            10s;
    client_body_timeout              10s;
    send_timeout                     10s;
    proxy_connect_timeout            10s;
    proxy_send_timeout               10s;
    proxy_read_timeout               10s;
    #lingering_time                  10s;
    #lingering_timeout               10s;
    #reset_timedout_connection       on;

    # mod_gzip configurations
    gzip                             on;
    gzip_http_version                1.1;
    gzip_comp_level                  6;
    gzip_min_length                  1k;
    gzip_vary                        on;
    #gzip_proxied                    any;
    #gzip_disable                    msie6;
    gzip_buffers                     8 16k;
    gzip_types                       text/xml text/plain text/css application/javascript application/x-javascript application/xml application/json application/rss+xml;

    # limit setting: fight DDoS attack, tune the numbers below according your application!!!
    # usage 1: limit rate/qps, define a limit zone rule: key=\$binary_remote_addr, name=qps_limit_per_ip, memerysize=10m, speed=50 per second
    #limit_req_zone                   \$binary_remote_addr zone=qps_limit_per_ip:10m rate=100r/s;
    # apply a limit zone rule: use qps_limit_per_ip rule, allow burst=10 requests into queue
    #limit_req                        zone=qps_limit_per_ip burst=10;
    # usage 2: limit concurrent connection, define a limit zone: key=binary_remote_addr, name=conn_limit_per_ip, memerysize=10m
    #limit_conn_zone                  \$binary_remote_addr zone=conn_limit_per_ip:10m;
    #limit_conn                       conn_limit_per_ip 100;

    # optimize cache
    #open_file_cache                 max=10000 inactive=20s;
    #open_file_cache_valid           30s;
    #open_file_cache_min_uses        2;
    #open_file_cache_errors          on;

    # others setting
    server_tokens                    off;
    autoindex                        off;
    #log_not_found                   off;
    #server_names_hash_max_size      2048;
    #server_names_hash_bucket_size   128;

    # access log setting
    #log_format                      access '[\$time_iso8601][\$remote_addr][\$http_x_forwarded_for]'
    #                                    '[\$status][\$bytes_sent][\$request_time][\$upstream_response_time][\$http_origin][\$var_cors_origin][\$request_method:\$request_uri]';
    log_format                       access '[\$time_iso8601][\$remote_addr][\$http_x_forwarded_for]'
                                        '[status=\$status][\$bytes_sent][\$request_time][\$upstream_response_time][\$http_origin][\$var_cors_origin][\$var_connection_header][\$server_port \$request_method \$scheme:/\$request_uri]';

    #access_log                      /var/log/nginx/access.log access;
    access_log                       /dev/null access;

    #include /etc/nginx/conf.d/*.conf;

    # Separate the following into independent configurations and import them through include
    #========default.conf==========================================================================

    map \$http_upgrade \$var_connection_header {
        default "";
        "~.+\$" "upgrade";
        #condition2 value;
    }

    map \$http_origin \$var_cors_origin {
        default "";
        "~^http[s]?://(.+\.)?example\.com\$" \$http_origin;
        "~^http[s]?://(.+\.)?example\.cn\$" \$http_origin;
    }

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites/*.conf;
}
EOF

  cat << EOF > "${global_nginx_home_path}"/conf/nginx_sni.conf.bak
# stream模块 监听 TCP 443 和 UDP 443，根据SNI分流，不解析协议内容（reality域名获取【https://myip.ms/xxx.xxx.xxx.xxx】，hysteria2域名获取【】）
# 原理（根据SNI分流）：1.监听443端口，2.根据协议类型分流（UDP【hysteria2】 & TCP【reality & web】），然后根据SNI区分TCP不同服务【reality & web】。
# 		1. UDP：只有 hysteria2 一种服务, 不用管SNI分流，但是需要域名Web支持http3（如果是自己的域名，可以托管到Cloudflare即可，如果是别人的域名，支持HTTP3 + TLS1.3 + X25519即可） 
# 		2. TCP: 区分 reality 和 web 服务，如果偷自己的域名则配置自己的域名（比如oss.xxxxx.com），如果偷别人域名的证书，则配置别人的域名（比如itunes.apple.com）
# docker镜像：			nginx:1.28-alpine
# docker容器：			docker run -d --user root --name nginx-quic --restart unless-stopped --network host -e TZ=Asia/Tokyo -v /opt/softs/nginx-quic/html:/usr/share/nginx/html -v /opt/softs/nginx-quic/conf:/etc/nginx -v /opt/softs/nginx-quic/certbot:/etc/letsencrypt nginx:1.28-alpine
# SSL证书：				WEB服务（CDN加速）使用Cloudflare证书，其他服务使用letsencrypt证书（HTTP方式）
# curl测试HTTP3：        apt install -y snapd && snap install curl && /snap/bin/curl -vk --http3-only  https://127.0.0.1:9443
# 监听UDP端口测试：		nc -ul 0.0.0.0 443
# 客户端测试UDP端口：		echo "test" | nc -u x.x.x.x 443
# 端口监听状态查询：		ss -lnp | grep 443
#
#========global====================================================================================
#user                                nobody nobody;
worker_processes                     auto;
worker_cpu_affinity                  auto;
worker_rlimit_nofile                 65535;

# [ debug | info | notice | warn | error | crit ] 
error_log                            /var/log/nginx/error.log notice;
pid                                  /var/run/nginx.pid;

#========events====================================================================================
events {
    use                              epoll;
    # count per work processer
    worker_connections               65535;
    #accept_mutex                    on;
    multi_accept                     on;
}

stream {
    # log setting[/var/log/nginx/access.log   /dev/null   /dev/stdout]
    #log_format                      sni_log '----- [\$time_iso8601][\$remote_addr] \$protocol SNI="\$ssl_preread_server_name" '
    #                                         'upstream=\$upstream_addr status=\$status time=\$session_time';
    #access_log                       /dev/null sni_log;

    map \$ssl_preread_server_name \$backend_name {
        # cloudflare cdn & vmess websocket
        oss.xxxxx.com reality_backend;
        #~*(xxxxx\.com)\$ web_backend_2;
        default web_backend;
    }

    upstream reality_backend {
        server 127.0.0.1:5443;
    }

    upstream hysteria2_backend {
        server 127.0.0.1:6443;
    }

    upstream web_backend {
        server 127.0.0.1:9443;
    }

    #upstream web_backend_2 {
    #    server 127.0.0.1:10443;
    #}

    server {
        listen 443;
        #listen [::]:443;

        ssl_preread    on;
        ## 开启proxy_protocol的话，Nginx会向所有的上游（不仅web_backend，还包括reality_backend 和 hysteria2_backend）发送 Proxy Protocol 协议头。
        ## 但是sing box不支持proxy_protocol协议头解析，会导致singbox服务异常
        ## 如果开启，可以使用【real_ip_header proxy_protocol;】读取客户端IP
        #proxy_protocol on;
        proxy_pass     \$backend_name;
    }

    server {
        listen 443 udp reuseport;
        #listen [::]:443 udp reuseport;

        proxy_pass    hysteria2_backend;
        #proxy_pass    web_backend;
        proxy_timeout 30s;
    }
}

http {
    include                          mime.types;
    default_type                     application/octet-stream;

    # TODO : zoro copy setting
    #####################################################################
    #                       #  sendfile  #  tcp_nopush  #  tcp_nodelay  #
    #####################################################################
    # API                   #     off    #      off     #      on       #
    # Small files (static)  #     on     #      off     #      on       #
    # Big files (static)    #     on     #      on      #      off      #
    #####################################################################
    sendfile                         off;
    tcp_nopush                       off;
    tcp_nodelay                      on;
    sendfile_max_chunk               128k;
    #send_lowat                      12000;

    # client setting
    # buffers setting, get memery pagesize command: [getconf PAGESIZE]
    client_header_buffer_size        4k;
    large_client_header_buffers      4 8k;
    client_body_buffer_size          64k;
    # TODO : if uploading a large file, please set a larger value separately.
    client_max_body_size             10m;
    client_body_in_single_buffer     on;
    #client_body_temp_path           /path/to/tmp/client_body_temp;

    # proxy setting
    proxy_buffering                  on;
    proxy_buffer_size                4k;
    proxy_buffers                    64 8k;
    #proxy_temp_path                 /path/to/tmp/proxy_temp;
    #proxy_max_temp_file_size        512k;
    #proxy_temp_file_write_size      64k;
    #proxy_cache_path                /path/to/tmp/proxy_cache levels=1:2 keys_zone=cache_one:512m inactive=1d max_size=2g;

    # keepalive setting
    keepalive_timeout                30s;
    keepalive_requests               100;

    # timeout setting
    client_header_timeout            5s;
    # TODO : if uploading a large file, please set a larger value separately.
    client_body_timeout              5s;
    send_timeout                     5s;
    proxy_connect_timeout            10s;
    proxy_send_timeout               10s;
    proxy_read_timeout               10s;
    # delayed shutdown enabled: on, off, always
    lingering_close                  on;
    lingering_time                   10s;
    lingering_timeout                5s;
    reset_timedout_connection        on;

    # mod_gzip configurations
    gzip                             on;
    gzip_comp_level                  6;
    gzip_min_length                  1k;
    gzip_vary                        on;
    gzip_proxied                     any;
    #gzip_http_version               1.1;
    #gzip_disable                    msie6;
    gzip_buffers                     8 16k;
    gzip_types                       text/plain text/xml text/css text/javascript application/json application/javascript application/x-javascript application/xml application/rss+xml application/xhtml+xml font/ttf font/otf image/svg+xml;
    gzip_static                      on;

    # open_file_cache--------------------
    open_file_cache                  max=1000 inactive=20s;
    open_file_cache_valid            30s;
    open_file_cache_min_uses         2;
    open_file_cache_errors           on;

    # limit setting: fight DDoS attack, tune the numbers below according your application!!!
    # usage 1: limit rate/qps, define a limit zone rule: key=\$binary_remote_addr, name=qps_limit_per_ip, memerysize=10m, speed=50 per second
    #limit_req_zone                   \$binary_remote_addr zone=qps_limit_per_ip:10m rate=100r/s;
    # apply a limit zone rule: use qps_limit_per_ip rule, allow burst=10 requests into queue
    #limit_req                        zone=qps_limit_per_ip burst=10;
    # usage 2: limit concurrent connection, define a limit zone: key=binary_remote_addr, name=conn_limit_per_ip, memerysize=10m
    #limit_conn_zone                  \$binary_remote_addr zone=conn_limit_per_ip:10m;
    #limit_conn                       conn_limit_per_ip 100;

    # optimize cache
    #open_file_cache                 max=10000 inactive=20s;
    #open_file_cache_valid           30s;
    #open_file_cache_min_uses        2;
    #open_file_cache_errors          on;
    
    # others setting
    server_tokens                    off;
    autoindex                        off;
    #log_not_found                   off;
    #server_names_hash_max_size      2048;
    #server_names_hash_bucket_size   128;

    # log setting[/var/log/nginx/access.log   /dev/null   /dev/stdout]
    log_format                       alertsyslog '[\$time_iso8601][\$remote_addr] \$arg_content';
    log_format                       access '[\$time_iso8601][\$remote_addr]'
                                        '[status=\$status][\$bytes_sent][\$request_time][\$upstream_response_time][\$http_origin][\$var_cors_origin][\$var_connection_header][\$server_port \$request_method \$scheme://\$host\$request_uri]';
    access_log                       /dev/null access;
    
    #include /etc/nginx/conf.d/*.conf;
    
    # Separate the following into independent configurations and import them through include
    #========default.conf==========================================================================

    ## client real ip, check module command: nginx -V 2>&1 | grep --color -o with-http_realip_module
    ## 1. Trust all possible CDN nodes (Cloudflare is listed here; please add other CDNs if available).
    #set_real_ip_from x.x.x.x/22;
    ## ..............
    #set_real_ip_from xxxx:xxxx::/32;
    ## 2. Specify a header containing the real IP address
    ## X-Forwarded-For is universal; almost all CDNs (CF-Connecting-IP is Cloudflare-specific) send X-Forwarded-For, and it supports multi-tiered CDN hybrid systems.
    #real_ip_header X-Forwarded-For;
    ## 3. Enable recursive DNS resolution: If multiple proxies are involved, enable recursive DNS resolution, and search for the first non-whitelisted IP address from the end to the beginning as the real IP address.
    #real_ip_recursive on;
    ## include /etc/nginx/conf.d/nginx_client_real_ip.conf;

    map \$http_upgrade \$var_connection_header {
        default "";
        "~.+\$" "upgrade";
        #condition2 value;
    }

    # TODO : Example configuration of cors, xxxxx.com (1/4)
    map \$http_origin \$var_cors_origin {
        default "";
        "~^http[s]?://(.+\.)?(xxxxx\.cn|xxxxx\.com)\$" \$http_origin;
        #"~^http[s]?://(.+\.)?xxxxx\.cn\$" \$http_origin;
    }

    #map \$uri \$file_type {
    #    ~*\.(html|htm)\$ html;
    #    ~*\.(css|js|eot|ttf|woff|woff2)\$ common;
    #    ~*\.(png|jpg|jpeg|gif|webp|svg|ico)\$ img;
    #    default other;
    #}
    
    # https://www.alibabacloud.com/help/zh/cdn/user-guide/set-the-nginx-cache-policy
    #map \$sent_http_content_type \$cache_control {
    #    text/html                "private, no-cache, must-revalidate";
    #    text/css                 "public, max-age=2592000";
    #    application/javascript   "public, max-age=2592000";
    #    ~^image/                 "public, max-age=31536003, immutable";
    #    ~^font/                  "public, max-age=31536003, immutable";
    #    ~^audio/                 "public, max-age=2592000";
    #    ~^video/                 "public, max-age=2592000";
    #    default                  "no-cache";
    #}
    #include /etc/nginx/conf.d/*.conf;
    #include /etc/nginx/sites/*.conf;

    upstream backend_vmess_websocket {
        ip_hash;
        server                       127.0.0.1:7443 weight=200 max_fails=1 fail_timeout=10s;
        keepalive                    100;
        #keepalived_requests         100;
        keepalive_timeout            60s;
    }
    
    # default 
    #server {
    #    listen 80 default_server;
    #    server_name _;
    #    return 444;
    #}

    # default 
    #server {
    #    listen 443 ssl default_server;
    #    server_name _;
    #    ssl_reject_handshake on;
    #}
    
    server {
        listen                       80;
        #listen                      [::]:80;
        #server_name                 xxx.com www.xxx.com;
        #return                       301 https://\$host\$request_uri;

        # use cloudflare ssl cert
        #certbot cert [Suitable for HTTP-01, but not suitable for DNS-01.]
        #certbot automatically creates a one-time temporary directory named .well-known and verification files, so these paths need to be publicly accessible.
        location /.well-known/acme-challenge/ {
            root                     /usr/share/nginx/html/xxxxx.com;
        }

        location / {
            return                   301 https://\$host\$request_uri;
        }
    }

    server {
        listen                       127.0.0.1:9443 quic reuseport;
        #listen                      127.0.0.1:9443 ssl proxy_protocol reuseport;
        listen                       127.0.0.1:9443 ssl reuseport;
        http2                        on;

        set_real_ip_from             127.0.0.1;
        real_ip_header               X-Forwarded-For;
        #real_ip_header              proxy_protocol;
        real_ip_recursive            on;

        # SSL setting
        ssl_certificate              /etc/letsencrypt/live/xxxxx.com/fullchain.pem;
        ssl_certificate_key          /etc/letsencrypt/live/xxxxx.com/privkey.pem;

        ssl_protocols                TLSv1.2 TLSv1.3;
        ssl_early_data               on;
        ssl_session_cache            shared:SSL:10m;
        ssl_session_timeout          10m;
        ssl_session_tickets          off;
        #ssl_ciphers                 ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305;
        #ssl_ecdh_curve              secp521r1:secp384r1:secp256r1:x25519;
        ssl_ciphers                  ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-GCM-SHA384;
        ssl_ecdh_curve               X25519:prime256v1:secp384r1:secp521r1;
        #ssl_prefer_server_ciphers    on;
        root                         /usr/share/nginx/html/xxxxx.com;

        # HTTP/3.
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        # Add Alt-Svc header to negotiate HTTP/3.
        add_header alt-svc 'h3=":443"; ma=86400';
        # Sent when QUIC was used
        add_header QUIC-Status \$http3;

        # vmess
        location /im/msg {
            proxy_redirect                       off;
            proxy_http_version                   1.1;
            proxy_set_header                     Host \$host;
            proxy_set_header                     X-Real-IP \$remote_addr;
            proxy_set_header                     X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header                     Upgrade \$http_upgrade;
            proxy_set_header                     Connection \$var_connection_header;
            proxy_pass                           http://backend_vmess_websocket;
        }

        location /my-web-demo {
            proxy_set_header   X-Real-IP \$remote_addr;
            proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header   Host \$host;
            proxy_pass         http://127.0.0.1:3001;
            proxy_http_version 1.1;
            proxy_set_header   Upgrade \$http_upgrade;
            proxy_set_header   Connection "upgrade";
        }

        location /myip {
            default_type text/plain;
            #return 200 "Your IP: \$remote_addr\nHeaders: \$http_x_forwarded_for";
            return 200 "Your IP: \$remote_addr";
        }

        location /files/ {
            charset                              utf-8;
            root                                 /usr/share/nginx/html;
            #autoindex                           on;
            auth_basic                           "Restricted Access - Please Login";
            auth_basic_user_file                 /etc/nginx/secrets/.htpasswd;
        }

        location /alertsys/event {
            default_type                         application/json;
            charset utf-8;
            if (\$arg_auth_code != "Abc123456") {
                return 403 '{"code":403,"msg":"invalid code"}';
            }
            access_log /var/log/nginx/alertsys.log alertsyslog;
            return 200 '{"code":200,"msg":"success"}';
        }

        location /alertsys/info/ {
            default_type text/plain;
            charset utf-8;
            if (\$arg_auth_code != "Abc123456") {
                return 403 'not allowed';
            }
            alias /var/log/nginx/;
            #autoindex on;
        }

        # default routing: (only go to one location)
        # html: always check for changes.
        # css/js use a different URL after each change.(version or hash)
        location = / {
            index                                index.html index.htm;
        }
        location / {
            try_files                            \$uri =404;
        }
    }

    #server {
    #    listen                       127.0.0.1:10443 quic reuseport;
    #    #listen                      127.0.0.1:10443 ssl proxy_protocol reuseport;
    #    listen                       127.0.0.1:10443 ssl reuseport;
    #    http2                        on;

    #    set_real_ip_from             127.0.0.1;
    #    real_ip_header               X-Forwarded-For;
    #    #real_ip_header              proxy_protocol;
    #    real_ip_recursive            on;

    #    # SSL setting
    #    ssl_certificate              /etc/letsencrypt/live/xxxxx.com/fullchain.pem;
    #    ssl_certificate_key          /etc/letsencrypt/live/xxxxx.com/privkey.pem;

    #    ssl_protocols                TLSv1.2 TLSv1.3;
    #    ssl_early_data               on;
    #    ssl_session_cache            shared:SSL:10m;
    #    ssl_session_timeout          10m;
    #    ssl_session_tickets          off;
    #    #ssl_ciphers                 ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305;
    #    #ssl_ecdh_curve              secp521r1:secp384r1:secp256r1:x25519;
    #    ssl_ciphers                  ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-GCM-SHA384;
    #    ssl_ecdh_curve               X25519:prime256v1:secp384r1:secp521r1;
    #    #ssl_prefer_server_ciphers    on;
    #    root                         /usr/share/nginx/html/xxxxx.com;

    #    # HTTP/3.
    #    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    #    # Add Alt-Svc header to negotiate HTTP/3.
    #    add_header alt-svc 'h3=":443"; ma=86400';
    #    # Sent when QUIC was used
    #    add_header QUIC-Status \$http3;

    #    location /myip {
    #        default_type text/plain;
    #        #return 200 "Your IP: \$remote_addr\nHeaders: \$http_x_forwarded_for";
    #        return 200 "Your IP: \$remote_addr";
    #    }

    #
    #    # default routing: (only go to one location)
    #    # html: always check for changes.
    #    # css/js use a different URL after each change.(version or hash)
    #    location = / {
    #        index                                index.html index.htm;
    #    }
    #    location / {
    #        try_files                            \$uri =404;
    #    }
    #}

}

EOF
}

nginx_config_vmess_websocket(){
  print_message "Nginx配置：代理 vmess(websocket) 服务，但不启用：${global_nginx_home_path}/conf/sites/01_vmess_domain.conf.bak"
  cat << EOF > "${global_nginx_home_path}"/conf/sites/01_vmess_domain.conf.bak
# 说明：域名+端口不能被其他服务占用，如果被占用，需将此文件配置合并到 跟域名端口对应的配置文件中
# 1、vmess协议监听的端口【7443】、websocket uri路径【/im/msg】：替换为vmess协议对应的端口、uri路径
# 2、绑定域名【xxx.xxx】：绑定的域名，比如 google.com
# 3、上传域名证书到该目录【/opt/softs/nginx-web/conf/certs/】：xxx.xxx.pem、xxx.xxx.key
# 4、生效配置，去除.bak后缀：${global_nginx_home_path}/conf/sites/vmess_domain.conf.bak
# 5、重启nginx
upstream backend_vmess_websocket {
	ip_hash;
	server                       127.0.0.1:7443 weight=200 max_fails=1 fail_timeout=10s;
	keepalive                    100;
	#keepalived_requests         100;
	keepalive_timeout            60s;
}

server {
	listen                       80 http2;
	server_name                  xxx.xxx;
	return                       301 https://\$host\$request_uri;
}

server {
	listen                       443 ssl http2;
	server_name                  xxx.xxx;

	# SSL setting
	ssl_certificate              /etc/nginx/certs/xxx.xxx.pem;
	ssl_certificate_key          /etc/nginx/certs/xxx.xxx.key;

	ssl_protocols                TLSv1.2 TLSv1.3;
	ssl_session_cache            shared:SSL:10m;
	ssl_session_timeout          10m;
	ssl_ciphers                  HIGH:!aNULL:!MD5;
	ssl_prefer_server_ciphers    on;
	root                         /usr/share/nginx/html;

	# vmess
	location /im/msg {
		proxy_pass                           http://backend_vmess_websocket;

		proxy_redirect                       off;
		proxy_http_version                   1.1;
		proxy_set_header                     Host \$host;
		proxy_set_header                     X-Real-IP \$remote_addr;
		proxy_set_header                     X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header                     Upgrade \$http_upgrade;
		proxy_set_header                     Connection \$var_connection_header;
	}

	# static web：建议这里放静态站点伪装，或者直接代理lobe_chat
	location / {
		index                                index.html index.htm;
		root                                 /usr/share/nginx/html;
		#expires                             2d;
		#add_header Cache-Control            "public";
	}
}
EOF
}

nginx_config_open_webui(){
  print_message "Nginx配置: 代理 open_webui 服务，但不启用：${global_nginx_home_path}/conf/sites/02_open_webui_domain.conf.bak"
  cat << EOF > "${global_nginx_home_path}"/conf/sites/02_open_webui_domain.conf.bak
# 说明：域名+端口不能被其他服务占用，如果被占用，需将此文件配置合并到 跟域名端口对应的配置文件中
# 1、open_webui端口【3000】：替换为open_webui监听的端口
# 2、绑定域名【xxx.xxx】：绑定的域名，比如 google.com
# 3、上传域名证书到该目录【/opt/softs/nginx-web/conf/certs/】：xxx.xxx.pem、xxx.xxx.key
# 4、生效配置，去除.bak后缀：${global_nginx_home_path}/conf/sites/vmess_domain.conf.bak
# 5、重启nginx
#
# docker run -d --name open-webui --restart unless-stopped -p 3000:8080 -e ENABLE_OPENAI_API=True \
#           -e OPENAI_API_BASE_URL=https://api.deepseek.com/v1 -e OPENAI_API_KEY=xxx \
#           -v open-webui:/app/backend/data ghcr.io/open-webui/open-webui:main
#

upstream backend_open_webui {
	ip_hash;
	server                       127.0.0.1:3000 weight=200 max_fails=1 fail_timeout=10s;
	keepalive                    100;
	#keepalived_requests         100;
	keepalive_timeout            60s;
}

server {
	listen                       80 http2;
	server_name                  xxx.xxx;
	return                       301 https://\$host\$request_uri;
}

server {
	listen                       443 ssl http2;
	server_name                  xxx.xxx;

	# SSL setting
	ssl_certificate              /etc/nginx/certs/xxx.xxx.pem;
	ssl_certificate_key          /etc/nginx/certs/xxx.xxx.key;

	ssl_protocols                TLSv1.2 TLSv1.3;
	ssl_session_cache            shared:SSL:10m;
	ssl_session_timeout          10m;
	ssl_ciphers                  HIGH:!aNULL:!MD5;
	ssl_prefer_server_ciphers    on;
	root                         /usr/share/nginx/html;

  # chat api: websocket
	location /api/v1/chats/ {
		proxy_pass                           http://backend_open_webui;
		proxy_redirect                       off;
		# proxy_http_version                 1.1;
		proxy_set_header                     Host \$host;
		proxy_set_header                     X-Real-IP \$remote_addr;
		proxy_set_header                     X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header                     Upgrade \$http_upgrade;
		proxy_set_header                     Connection \$var_connection_header;

		# 不缓存，支持流式输出
		# 关闭缓存
		proxy_cache off;
		# 关闭代理缓冲
		proxy_buffering off;
		# 开启分块传输编码
		chunked_transfer_encoding on;
		# 开启TCP NOPUSH选项，禁止Nagle算法
		tcp_nopush on;
		# 开启TCP NODELAY选项，禁止延迟ACK算法
		tcp_nodelay on;
		# 设定keep-alive超时时间为65秒
		keepalive_timeout 300;
	}

	# default
	location / {
		proxy_pass                           http://backend_open_webui;
		proxy_redirect                       off;
		# proxy_http_version                 1.1;
		proxy_set_header                     Host \$host;
		proxy_set_header                     X-Real-IP \$remote_addr;
		proxy_set_header                     X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header                     Upgrade \$http_upgrade;
		proxy_set_header                     Connection \$var_connection_header;
	}
}
EOF
}

nginx_config_lobe_chat(){
  print_message "Nginx配置: 代理 lobe_chat 服务，但不启用：${global_nginx_home_path}/conf/sites/03_lobe_chat_domain.conf.bak"
  cat << EOF > "${global_nginx_home_path}"/conf/sites/03_lobe_chat_domain.conf.bak
# 说明：域名+端口不能被其他服务占用，如果被占用，需将此文件配置合并到 跟域名端口对应的配置文件中
# 1、lobe_chat端口【3210】：替换为lobe_chat监听的端口
# 2、绑定域名【xxx.xxx】：绑定的域名，比如 google.com
# 3、上传域名证书到该目录【/opt/softs/nginx-web/conf/certs/】：xxx.xxx.pem、xxx.xxx.key
# 4、生效配置，去除.bak后缀：${global_nginx_home_path}/conf/sites/vmess_domain.conf.bak
# 5、重启nginx
#
# openai 服务启动：
# docker run -d --name lobe-chat --restart unless-stopped -p 3210:3210 -e ACCESS_CODE=此处自定义你的登录密码 \
#           -e OPENAI_MODEL_LIST=-all,+gpt-4o,+gpt-4o-mini -e OPENAI_API_KEY=xxxx lobehub/lobe-chat
#
# deepseek 服务启动：
# docker run -d --name lobe-chat --restart unless-stopped -p 3210:3210 -e ACCESS_CODE=此处自定义你的登录密码 \
#           -e ENABLED_OPENAI=0 -e DEEPSEEK_MODEL_LIST=-all,+deepseek-reasoner \
#           -e DEEPSEEK_PROXY_URL=https://api.deepseek.com\
#           -e DEEPSEEK_API_KEY=xxxx lobehub/lobe-chat

upstream backend_lobe_chat {
	ip_hash;
	server                       127.0.0.1:3210 weight=200 max_fails=1 fail_timeout=10s;
	keepalive                    100;
	#keepalived_requests         100;
	keepalive_timeout            60s;
}

server {
	listen                       80 http2;
	server_name                  xxx.xxx;
	return                       301 https://\$host\$request_uri;
}

server {
	listen                       443 ssl http2;
	server_name                  xxx.xxx;

	# SSL setting
	ssl_certificate              /etc/nginx/certs/xxx.xxx.pem;
	ssl_certificate_key          /etc/nginx/certs/xxx.xxx.key;

	ssl_protocols                TLSv1.2 TLSv1.3;
	ssl_session_cache            shared:SSL:10m;
	ssl_session_timeout          10m;
	ssl_ciphers                  HIGH:!aNULL:!MD5;
	ssl_prefer_server_ciphers    on;
	root                         /usr/share/nginx/html;

	# default
	location / {
		proxy_pass                           http://backend_lobe_chat;
		proxy_redirect                       off;
		# proxy_http_version                 1.1;
		proxy_set_header                     Host \$host;
		proxy_set_header                     X-Real-IP \$remote_addr;
		proxy_set_header                     X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header                     Upgrade \$http_upgrade;
		proxy_set_header                     Connection \$var_connection_header;
	}
}
EOF
}

env_init() {
  if [ -e "$global_nginx_home_path" ]; then
    curr_time=$(date +"%Y%m%d_%H%M%S")
    backup_file="${global_nginx_home_path}_bak_${curr_time}"
    print_message "正在备份：$global_nginx_home_path  -> ${backup_file}"
    cp -rp "$global_nginx_home_path" "$backup_file"
  fi
  rm -rf "$global_nginx_home_path"
  mkdir -p "$global_nginx_home_path"
  #mkdir "$global_nginx_home_path"/{conf,logs,html,certbot,openssl,tmp}
  mkdir "$global_nginx_home_path"/certbot
  mkdir "$global_nginx_home_path"/conf
  mkdir "$global_nginx_home_path"/logs
  mkdir "$global_nginx_home_path"/html
  mkdir "$global_nginx_home_path"/tmp
  mkdir "$global_nginx_home_path"/conf/originals
  mkdir "$global_nginx_home_path"/conf/certs
  mkdir "$global_nginx_home_path"/conf/secrets
}

nginx_create_http_htpasswd() {
  # global_nginx_home_path=/opt/softs/nginx-quic
  #mkdir "$global_nginx_home_path"/conf/secrets
  #printf "test:$(openssl crypt 123456 $(openssl rand -base64 8))\n" > /etc/nginx/.htpasswd
  # 密码： openssl passwd -apr1 Abc123456
  # echo "ghostman:\$apr1\$IZ9eM22x\$zfAtz9iHXjtPrqF41WO5V1" > "$global_nginx_home_path"/conf/secrets/.htpasswd
  echo 'ghostman:$apr1$IZ9eM22x$zfAtz9iHXjtPrqF41WO5V1' > "$global_nginx_home_path"/conf/secrets/.htpasswd
}


# 主流程 ======= 开始 =======================
# 参数解析：版本号、安装目录、时区
# ./nginx_install.sh 1.28-alpine /opt/softs nginx-quic America/Los_Angeles
# ./nginx_install.sh 1.27.1 /opt/softs nginx-web America/Los_Angeles
global_nginx_version="$1"
global_nginx_home_path="$2"
global_nginx_container_name="$3"
global_nginx_time_zone="$4"

if [ "$global_nginx_version" = "" ]; then
  global_nginx_version="1.27.1"
fi

if [ "$global_nginx_container_name" = "" ]; then
  global_nginx_container_name="nginx-web"
fi

global_nginx_full_image="nginx:${global_nginx_version}"
if [ "$global_nginx_home_path" = "" ]; then
  global_nginx_home_path="/opt/softs"
fi
global_nginx_home_path=$(readlink -f "$global_nginx_home_path")
global_nginx_home_path="${global_nginx_home_path}/$global_nginx_container_name"

# 确保 docker 已安装
if ! command_exists docker; then
  print_message "docker 程序：未安装；如果使用tasks_run脚本自动执行，请在该任务前添加【docker_install latest】任务"
  exit $global_code_failure
fi

# 确保 docker 已运行
if ! docker_running; then
  print_message "docker 进程：未启动"
  docker_start
  if ! docker_running; then
    print_message "docker 进程：启动失败"
    exit $global_code_failure
  fi
  print_message "docker 进程：启动成功"
fi

# 检查容器是否存在
if docker inspect "$global_nginx_container_name" > /dev/null 2>&1; then
  # 检查容器运行状态
  container_status=$(docker inspect -f '{{.State.Running}}' "$global_nginx_container_name")
  print_message "nginx 容器：running=${container_status}"
  if [ ! "$container_status" = "true" ]; then
    docker start "$global_nginx_container_name"
  fi
  container_status=$(docker inspect -f '{{.State.Running}}' "$global_nginx_container_name")
  print_message "nginx 容器：running=${container_status}"
  exit 0
fi

# 如果镜像不存在，则拉取
if ! nginx_image_exists; then
  if ! nginx_image_pull; then
    print_message "拉取镜像失败：$global_nginx_full_image"
    exit $global_code_failure
  fi
  if ! nginx_image_exists; then
    print_message "拉取镜像失败：$global_nginx_full_image"
    exit $global_code_failure
  fi
fi

# 环境初始化
if ! env_init; then
  print_message "环境初始化失败"
fi

nginx_config_default
nginx_create_http_htpasswd
nginx_config_main
nginx_config_vmess_websocket
nginx_config_open_webui
nginx_config_lobe_chat
nginx_container_create
docker restart "$global_nginx_container_name"


# 返回脚本执行结果
code=$global_code_failure
if docker inspect "$global_nginx_container_name" > /dev/null 2>&1; then
  container_status=$(docker inspect -f '{{.State.Running}}' "$global_nginx_container_name")
  if [ "$container_status" = "true" ]; then
    code=0
  fi
fi
exit $code

