#!/bin/bash


#docker_image={{local_repository_category}}/base/nginx:1.22-alpine-www
docker_image=registry.cn-shanghai.aliyuncs.com/elvin/nginx:1.22-alpine-www

docker pull ${docker_image} &>/dev/null

docker rm -f nginx-www  &>/dev/null
docker run -d --name nginx-www  \
--restart=always \
--memory 64M \
-p {{deploy_yml_port}}:80 \
-v /data/www:/data/www \
-v /etc/localtime:/etc/localtime:ro \
${docker_image}

