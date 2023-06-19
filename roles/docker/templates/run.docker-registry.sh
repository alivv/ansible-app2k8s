#!/bin/bash
# run.docker-registry.sh
# deploy docker registry +ui
# deploy by ansible {{ ansible_date_time.date }}
# By Elvin 

########## conifg

#data directory
data_dir={{ registry_data_dir }}
mkdir -p $data_dir
cd $data_dir

#https cert
domain_name={{ registry_domain_name }}
download_url={{ registry_download_url }}
if [  ! -e ${domain_name}.key -o  ! -e ${domain_name}.pem ];then
curl -so ${domain_name}.key    ${download_url}/${domain_name}.key
curl -so ${domain_name}.pem ${download_url}/${domain_name}.pem
fi

#create passworld file, user {{ registry_username }} passworld {{ registry_password }} 
docker run --rm registry.cn-hangzhou.aliyuncs.com/elvin/htpasswd {{ registry_username }} {{ registry_password }} >htpasswd
#alivv/htpasswd


#Create Network {{ registry_net_name }}
if [ $(docker network ls |grep {{ registry_net_name }} |wc -l) -ne 1 ];then
    docker network create --subnet 10.20.20.0/24 --gateway 10.20.20.1 {{ registry_net_name }}
fi

########## container

#registry-srv
docker rm -f registry-srv &>/dev/null
docker run -dit --name registry-srv \
--privileged=true --restart=always \
--net {{ registry_net_name }} -p 443:443 \
--memory 512M \
-v $data_dir:/var/lib/registry \
-v /etc/localtime:/etc/localtime:ro \
-e REGISTRY_AUTH=htpasswd \
-e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
-e REGISTRY_AUTH_HTPASSWD_PATH=/var/lib/registry/htpasswd \
-e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
-e REGISTRY_STORAGE_DELETE_ENABLED=true \
-e REGISTRY_HTTP_TLS_KEY=/var/lib/registry/${domain_name}.key \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/var/lib/registry/${domain_name}.pem \
registry.cn-hangzhou.aliyuncs.com/elvin/registry:latest
# registry:latest

#registry-ui
docker rm -f registry-ui  &>/dev/null
docker run -d --name registry-ui \
--restart=always \
--memory 64M \
--net {{ registry_net_name }} -p {{ registry_ui_port }}:80 \
-v /etc/localtime:/etc/localtime:ro \
-e REGISTRY_URL=https://registry-srv:443 \
-e PULL_URL=${domain_name} \
-e DELETE_IMAGES=true \
-e REGISTRY_TITLE="Docker registry" \
registry.cn-hangzhou.aliyuncs.com/elvin/docker-registry-ui:1.5-static
# joxit/docker-registry-ui:1.5-static


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
