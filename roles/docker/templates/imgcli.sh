#!/bin/bash
#cnetos7,docker-ce,registry v2
#Docker registry 私有仓库镜像查询、删除、上传、下载

#Author  Elven <elven89@qq.com>
#Blog    http://www.cnblogs.com/elvi/p/8384675.html

#root
[[ $UID -ne 0 ]] && { echo "Run in root user !";exit; }

#need jq ,get json data
[[ -f /usr/bin/jq ]] || { 
  echo 'install jq';
  [[ -f /etc/redhat-release ]] && { yum install -y jq &>/dev/null; }
  [[ -f /etc/debian_version ]] && { sudo apt-get update;sudo apt-get -y install jq; }
 }
[[ -f /usr/bin/jq ]] || { echo 'install jq error !';exit; }

#参数 variable
#用户认证 用户:密码
#U="test:password"
U="{{ registry_username }}:{{ registry_password }}"
#registry容器名称,默认registry
RN=${RN:-registry-srv}
#访问网址,默认localhost:5000
# HUB_URL=${HUB:-localhost:5000}
HUB_URL=https://{{ registry_domain_name }}
#var set
HUB=$(echo $HUB_URL |sed "s#http.*://##")
if [[ -z $U ]];then
    login_U="" ; login_D=""
else
    login_U="-k -u $U"
    login_D="-u $(echo $U |cut -d ":" -f 1) -p $(echo $U |cut -d ":" -f 2)"
fi

#检测 check
function Check_hub() {
api_check=$(curl -s -m 2 $login_U $HUB_URL/v2/_catalog)
if [[ -z $api_check ]];then
    echo -e "\033[31m$HUB_URL 访问失败\033[0m";
    exit 1
elif [[ $api_check = *authentication* ]];then
    echo "$HUB 需要账户认证"
    exit
elif [[ $api_check = *repositories* ]];then
    #echo "$HUB check OK"
    ls -l &>/dev/null
else
    echo -e "\033[31m$HUB_URL 访问失败\033[0m";
    exit 1
fi
}

#查询images
function Select_img() {
IMG=$(curl -s -m 2 $login_U $HUB_URL/v2/_catalog |jq .repositories |awk -F'\"' '/\"/{print $2}')
[[ $IMG = "" ]] && { echo -e "\033[31m$HUB 没有docker镜像\033[0m";exit; }
#echo "$HUB Docker镜像："
for n in $IMG;
  do
  TAG=$(curl -s -m 2 $login_U $HUB_URL/v2/$n/tags/list |jq .tags |awk -F'\"' '/\"/{print $2}')
    for t in $TAG;
    do
      echo "$n:$t";
    done
done
}

registry_check() {
#判断registry是否存在，只能在registry宿主机运行
#[[ -f /usr/bin/docker ]] || echo 'No docker !'
[[ -z $(docker ps |grep " $RN$") ]] && { exit; }
}

registry_clean() {
#registry垃圾回收;只能在registry宿主机运行
echo "本地清理 Clean $RN ..."
docker exec $RN bin/registry garbage-collect /etc/docker/registry/config.yml &>/dev/null
docker restart $RN &>/dev/null
}

#删除images
function Delete_img() {
for n in $IMGS;
do
  IMG=${n%%:*}
  TAG=${n##*:}
  i=1
  [[ "$IMG" == "$TAG" ]] && { TAG=latest; n="$n:latest"; }
  Digest=`curl -m 1 $login_U --header "Accept: application/vnd.docker.distribution.manifest.v2+json" -Is  ${HUB_URL}/v2/${IMG}/manifests/${TAG} |awk '/digest|Digest/ {print $NF}'`
  [[ -z "$Digest" ]] && { echo -e "\033[31m$IMG:$TAG  镜像不存在\033[0m";} || { 
    URL="${HUB_URL}/v2/${IMG}/manifests/${Digest%?}"
    Rs=$(curl -m 1 -Is $login_U -X DELETE --header "Accept: application/vnd.docker.distribution.manifest.v2+json" ${URL}|awk '/HTTP/ {print $2}')
    [[ $Rs -eq 202 ]] && { let i++;echo "$n  删除成功"; } || { echo -e "\033[31m$n  删除失败\033[0m"; } }
done
#垃圾回收
[[ "$i" -gt 1 ]] && { registry_check;registry_clean; }
}

#删除镜像所在目录(清除所有 -dd .* )
#简单高效,删库跑路，必备技能
function Delete_img_a() {
[[ -z $(docker ps |grep " $RN$") ]] && { echo "$RN容器不存在!";exit; }
for n in $IMGS;
do
  IMG="${n%%:*}"
  docker exec $RN rm -rf /var/lib/registry/docker/registry/v2/repositories/$IMG
done
registry_clean
}

#上传 push
function Push() {
[[ -n $login_D ]] && { echo -n "$HUB ";docker login $login_D $HUB 2>/dev/null ; }
for IMG in $IMGS;
do
  echo -e "\033[33m docker push $IMG to $HUB \033[0m"
  docker tag $IMG $HUB/$IMG
  docker push $HUB/$IMG
  docker rmi $HUB/$IMG &>/dev/null
done
[[ -n $login_D ]] && { docker logout $HUB &>/dev/null ; }
}

#下载 pull
function Pull() {
[[ -n $login_D ]] && { echo -n "$HUB ";docker login $login_D $HUB 2>/dev/null ; }
for IMG in $IMGS;
do
  echo -e "\033[33m dokcer pull $IMG from $HUB \033[0m"
  docker pull $HUB/$IMG
  docker tag $HUB/$IMG $IMG
  docker rmi $HUB/$IMG &>/dev/null
done
[[ -n $login_D ]] && { docker logout $HUB &>/dev/null ; }
}

case "$1" in 
  "-h")
  echo  
  echo "#默认查询images  $HUB"
  echo "# -pull img1 img2 #上传 -push #下载"
  echo "# -h #帮助 -d #删除 -c 清理 -dd img #删除所有img镜像"
  echo 
  echo "#示例:"
  echo "imgcli -push nginx:1.1 nginx:1.2"
  echo "imgcli nginx"
  echo "imgcli -d nginx:1.1 nginx:1.2 "
  echo "imgcli -dd nginx #删除nginx所有版本"
  echo 
  echo "#临时定义仓库url地址hub.test.com:5000(默认 $HUB)"
  echo "env HUB=hub.test.com:5000 imgcli -d nginx:1.1 "
  echo  
;;
  "-d")
  Check_hub
  IMGS=${*/-dd/}
  IMGS=${IMGS/-d/}
  Delete_img
;;
  "-dd")
  IMGS=${*/-dd/}
  IMGS=${IMGS/-d/}
  Delete_img_a
;;
  "-pull")
  IMGS=${*/-pull/}
  Pull
;;
  "-push")
  IMGS=${*/-push/}
  Push
;;
  "-c")
  registry_clean
;;
  '')
  Check_hub
  Select_img
;;
  *)
  Check_hub
  Select_img |grep "$1"
;;
esac
