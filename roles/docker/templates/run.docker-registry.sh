#!/bin/bash
#run.docker-registry.ui.sh
#docker-registry +ui
# By Elvin , update 2024-3-27

########## conifg

#data directory
data_dir={{ registry_data_dir }}
mkdir -p $data_dir/conf
cd $data_dir

#https cert
domain_name={{ registry_domain_name }}
download_url={{ registry_download_url }}
if [  ! -f conf/${domain_name}.key -o  ! -f conf/${domain_name}.pem ];then
curl -so conf/${domain_name}.key    ${download_url}/${domain_name}.key
curl -so conf/${domain_name}.pem ${download_url}/${domain_name}.pem
fi

#create passworld file, user {{ registry_username }} passworld {{ registry_password }} 
if [ ! -f conf/htpasswd ];then
docker run --rm registry.aliyuncs.com/elvin/htpasswd {{ registry_username }} {{ registry_password }} >conf/htpasswd
fi

#Create Network {{ registry_net_name }}
if [ $(docker network ls |grep {{ registry_net_name }} |wc -l) -ne 1 ];then
    docker network create --subnet 10.20.20.0/24 --gateway 10.20.20.1 {{ registry_net_name }}
fi

#https
#docker exec -it registry-ui cat /etc/nginx/conf.d/default.conf |egrep -v "#"
cat > conf/https.conf << EOF
server {
    listen 80;
    listen              443 ssl;
    server_name         _;
    ssl_protocols       TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers         EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_certificate     /etc/nginx/conf.d/${domain_name}.pem;
    ssl_certificate_key /etc/nginx/conf.d/${domain_name}.key;
    root   /usr/share/nginx/html;

    client_max_body_size 0;
    chunked_transfer_encoding on;
    proxy_ssl_server_name on;
    proxy_buffering off;
    proxy_request_buffering off; 
    proxy_ignore_headers "X-Accel-Buffering";

    location /v2 {
        if (\$http_user_agent ~ "^(docker\/1\.(3|4|5(?!\.[0-9]-dev))|Go ).*$" ) {
            return 404;
        }
        proxy_http_version 1.1;
        proxy_pass http://registry-srv;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

chown 101 -R conf

########## container

#registry-srv
docker rm -f registry-srv &>/dev/null
docker run -dit --name registry-srv \
--privileged=true --restart=always \
--net {{ registry_net_name }} \
--memory 4096M \
-v $data_dir:/var/lib/registry \
-v /etc/localtime:/etc/localtime:ro \
-e REGISTRY_AUTH=htpasswd \
-e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
-e REGISTRY_AUTH_HTPASSWD_PATH=/var/lib/registry/conf/htpasswd \
-e REGISTRY_HTTP_ADDR=0.0.0.0:80 \
-e REGISTRY_STORAGE_DELETE_ENABLED=true \
-e REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin="[https://${domain_name}]" \
registry.aliyuncs.com/elvin/registry:2.8

#registry-ui
docker rm -f registry-ui  &>/dev/null
docker run -d --name registry-ui \
--restart=always \
--memory 256M \
--net {{ registry_net_name }} -p 80:80 -p 443:443 \
-v /etc/localtime:/etc/localtime:ro \
-v $data_dir/conf:/etc/nginx/conf.d \
-e PULL_URL=${domain_name} \
-e DELETE_IMAGES=true \
-e REGISTRY_TITLE="Docker registry" \
-e NGINX_PROXY_PASS_URL=http://registry-srv \
-e SINGLE_REGISTRY=true \
-e SHOW_CATALOG_NB_TAGS=true \
-e REGISTRY_SECURED=true \
registry.aliyuncs.com/elvin/docker-registry-ui:2

########## 

# set hosts
# echo "ip {{ registry_domain_name }}" >>/etc/hosts

# docker login {{ registry_domain_name }}

# #images push test
# docker pull alpine:3.12
# docker tag  alpine:3.12  {{ registry_domain_name }}/demo/alpine:3.12
# docker push {{ registry_domain_name }}/demo/alpine:3.12

# #remove
# docker rm -f registry-srv 
# docker rm -f registry-ui 
# docker network rm {{ registry_domain_name }}
