#!/bin/bash
# By Elvin, 2023-03-06
# blog.elvin.vip

# base ubuntu:focal
# ansible 2.7.18

sudo docker rm -f ansible-app2k8s &>/dev/null 
sudo docker run -dit --net=host \
--name ansible-app2k8s -h app2k8s \
-w /data/ansible-app2k8s \
-v /tmp:/tmp \
-v /etc/hosts:/etc/hosts \
-v ~/.ssh:/root/.ssh \
-v /data/ansible-app2k8s:/data/ansible-app2k8s \
registry.cn-shanghai.aliyuncs.com/elvin/ansible:2.7.18-focal 

sudo docker ps -l
