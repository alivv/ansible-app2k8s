<h3 align="center">ansible-app2k8s</h3>

[中文](README.cn.md) | [English](README.en.md)


#### #1 介绍

- 使用 ansible 管理和部署服务到 kubernetes  
- 适用于项目容器化，多套 k8s 环境的管理，可结合`CICD`工具做`DevOps`  
- 来自于项目实践,已部署多套 k8s 环境  
    - [自建 k8s](https://www.cnblogs.com/elvi/p/8976305.html)  
    - [阿里云 ACK](https://help.aliyun.com/product/85222.html)  
    - [腾讯云 TEK](https://cloud.tencent.com/document/product/457)  
    - [华为云 CCE](https://support.huaweicloud.com/cce/index.html)
    - [AWS EKS](https://docs.aws.amazon.com/zh_cn/eks/latest/userguide/what-is-eks.html)  
    - [微软云 AKS](https://learn.microsoft.com/zh-cn/azure/aks/)  

#### #2 主要功能  

- 镜像构建并推送到镜像仓库  
- 环境初始化(创建 namespace、储存卷、驱动等)  
- 部署监控(prometheus、grafana、loki)  
- 构建与部署服务到 k8s(主要用途)  

#### #3 运行环境

- 系统 Ubuntu 20
- ansible 2.7 (高版本可能出现语法兼容性问题)
- kubenertes(能被`kubectl`客户端连接即可)

#### #4 原理与结构

原理很简单，使用`ansible`管理模板，调用`kubectl`执行部署  
ansible-templates -> deploy.yml -> kubectl -> kubenertes
![](https://imgs.elvin.vip/2023/app2k8s-1.png)
执行过程使用`tag`标记，如`-t deploy`执行`deploy`部分  
根据执行过程，大致分为以下步骤模块

- base-build 基础镜像构建(docker build)
- push 推送公共镜像到镜像仓库(docker pull)
- init 环境初始化(如创建 namespace)
- monitor 监控警报(如 prometheus)
- build 构建服务镜像(docker build)
- deploy 部署服务(kubectl apply )
- ingress 配置域名访问(7 层代理)

模板目录 roles/k8s/templates  
根据服务类别分为如下子目录

- base 基础镜像 dockerfile
- ingress 域名解析配置
- init 环境初始化 yaml 文件
- java jar包构建镜像和部署模板
- jetty 使用`jetty`的服务构建和部署模板
- monitor 监控警报相关 yaml
- ms 没有单独参数文件的微服务部署模板
- nignx 前端静态使用 nginx 容器的部署模板

针对不同k8s环境如dev、prod,使用各自参数配置如储存、镜像仓库、资源限制等  
使用ansible -i 指定inventory路径并使用对应的组变量
如dev环境的k8s配置文件 group_vars/dev/k8s.yml 
服务app-v1的dev环境配置 group_vars/dev/k8s_apps/app-v1.yml
prod环境使用对应配置路径 group_vars/prod/k8s_apps/app-v1.yml

**运行截图**
![](https://imgs.elvin.vip/2023/k8s_ansible_cli_v1.jpg)

#### #5 dev 环境准备与配置  

##### #5.1 快速安装 k8s  

```bash
export Ver=1.22.16 #k8s版本
curl -ks http://elvin.vip/ks/k8s/k8s.master.ha.sh |bash

# 参考https://www.cnblogs.com/elvi/p/8976305.html 
```

##### #5.2 获取 ansible-app2k8s  

```bash
mkdir -p /data/ansible-app2k8s
cd /data/ansible-app2k8s
#gitee 
git clone https://gitee.com/alivv/ansible-app2k8s.git ./

#github 
#git clone https://github.com/alivv/ansible-app2k8s.git ./
```

##### #5.3 运行 ansible-app2k8s 容器

> 为保证运行`ansible`版本一致，我做了`ansible`镜像  
```bash
#查看shell
cat /data/ansible-app2k8s/files/run.ansible-app2k8s.sh
```

```bash
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
```
```bash
#运行容器 ansible-app2k8s
bash /data/ansible-app2k8s/files/run.ansible-app2k8s.sh

#配置别名
alias app2k8s='docker start ansible-app2k8s ; docker exec -it ansible-app2k8s bash'

#linux
echo "alias app2k8s='docker start ansible-app2k8s  ; docker exec -it ansible-app2k8s bash'" >>~/.bashrc

#macOS
echo "alias app2k8s='sudo docker start ansible-app2k8s  ; sudo docker exec -it ansible-app2k8s bash'" >>~/.zshrc

#进入ansible-app2k8s容器(Ctrl+d退出)
app2k8s

#查看ansbile版本
ansible --version
```

##### #5.4 初始化 docker-build 节点  

> 本实例把多个功能部署在 docker-build 单节点  
> 为了安全,实际可根据需求可拆分为多个节点

###### #5.4.1 更改配置  

配置 dev 节点 env/dev/k8s.inv

```bash
#配置dev环境节点信息 env/dev/k8s.inv
cat > env/dev/k8s.inv <<EOF
[dev:children]
k8s-node
docker-build

[docker-build]
build-node1        ansible_ssh_host=192.168.23.45
[k8s-node]
k8s-node1          ansible_ssh_host=192.168.23.30

[k8s:children]
k8s-node
[docker:children]
docker-build
registry
[registry]
build-node1
EOF

#IP地址换自己的,节点需要免密登录
#节点需要安装python2
# apt install -y python python2 python-apt
# ln -fs /usr/bin/python2 /usr/bin/python
```

配置 dev 环境参数 group_vars/dev/k8s.yml

```bash
#修改配置IP地址

k8s_version: 1.22.16

kubectl_node: 192.168.23.45
deploy_yml_node: 192.168.23.45
```

ansible 测试

```bash
ansible -i env/dev all -m ping

#获取节点变量
ansible -i env/dev all -m setup
```

###### #5.4.2 安装`docker-registry`、`nfs-server`、`yml-node`

```bash
#安装docker,docker-py(ansible构建镜像依赖)
ansible-playbook docker.yml -D -i env/dev -l docker-build -t docker,py,job

#部署docker-registry作为镜像仓库
ansible-playbook docker.yml -i env/dev -D -l registry -t registry,registry-auth
#增加镜像仓库host解析
ansible-playbook docker.yml -i env/dev -D -t hosts-registry

#yml文件存放节点
ansible-playbook docker.yml -i env/dev -D -l docker-build -t yml-node

#安装nfs服务和创建nfs目录,创建容器存储卷PVC使用
ansible-playbook nfs.yml -i env/dev -D -l docker-build -t nfs-server

#使用nfs储存卷,k8s节点需安装nfs client
ansible-playbook nfs.yml -i env/dev -D -l k8s
```

###### #5.4.3 安装配置 kubectl

`拷贝`k8s 节点配置 /etc/kubernetes/admin.conf  
`替换`本实例配置 roles/k8s/files/kubeconfig-dev.yml  
可手动配置kubeconfig,文件路径配置在group_vars/dev/k8s.yml  

```bash
#安装配置kubectl命令行
ansible-playbook k8s.yml -i env/dev -D -l build-node1 -t kubectl,kubeconfig

#kubectl测试命令 kubectl get nodes 
ansible-playbook k8s.yml -i env/dev -D -t kubectl-test
```

###### #5.5 ansible-app2k8s 测试

```bash
#查看帮助
ansible-playbook k8s.yml -i env/dev -D -t h

#查看资源列表
ansible-playbook k8s.yml -i env/dev -D -t list
```

构建镜像测试

```bash
#查看base基础镜像dockerfile列表
ansible-playbook k8s.yml -i env/dev -D -t baselist

#构建镜像nginx_1.22-alpine-www
ansible-playbook k8s.yml -i env/dev -D -t base-build -e baselist=nginx_1.22-alpine-www

#构建完成后打开镜像仓库web查看镜像
#默认账户密码 admin docker
#添加本地host解析后打开 http://hub.elvin.vip
```

#### #6 app2k8s 部署服务到 k8s

##### #6.1 推送公共镜像到镜像仓库

```bash
#查看列表
ansible-playbook k8s.yml -i env/dev -D -t pushlist

#推送所有(有点耗时)
ansible-playbook k8s.yml -i env/dev -D -t push -e pushlist=all
```

##### #6.2 k8 环境初始化

```bash
#查看yml列表
ansible-playbook k8s.yml -i env/dev -D -t initlist

#执行所有
ansible-playbook k8s.yml -i env/dev -D -t init -e initlist=all
```

##### #6.3 部署监控 prometheus、grafana、prometheus-adapter、loki

```bash
#警报通知使用钉钉机器人,需要改为自己的机器人tonken
grep notice_dingtalk_token group_vars/dev/k8s_ui.yml

#查看yml列表
ansible-playbook k8s.yml -i env/dev -D -t monitorlist

#执行所有yml
ansible-playbook k8s.yml -i env/dev -D -t monitor
```
grafana默认用户密码 `admin` `grafana`  
添加loki数据源地址 http://loki:3100  
添加prometheus数据库源地址 http://prometheus:9090    
grafana模板 roles/k8s/templates/monitor/grafana-template/  
![](https://imgs.elvin.vip/2023/grafana-datasources.jpg) 

##### #6.4 部署服务到 k8s

```bash
#查看app列表
ansible-playbook k8s.yml -i env/dev -D -t applist

#测试,构建与部署app-v1
ansible-playbook k8s.yml -i env/dev -D -t build,deploy -e applist=app-v1

#构建与部署全部
ansible-playbook k8s.yml -i env/dev -D -t build,deploy -e applist=all

```

##### #6.5 域名解析 ingress

```bash
ansible-playbook k8s.yml -i env/dev -D -t ingress
```
查看ingress配置,浏览器打开网址查看如下:
![](https://imgs.elvin.vip/2023/ingess-demo1.jpg)

#### #7 部署验证与清理

```bash
#添加本机hosts解析
ansible-playbook dev.yml -i env/dev -D -t hosts-local

#查看已配置网址列表,浏览器打开测试
ansible-playbook dev.yml -i env/dev -t url
```

**测试完成后,清理 k8s 的 dev 部署**

```bash
#删除ingress
ansible-playbook k8s.yml -i env/dev -D -t ingress-rm

#删除dev环境服务
ansible-playbook k8s.yml -i env/dev -D -t rm -e applist=all

#删除监控
ansible-playbook k8s.yml -i env/dev -D -t monitor-rm

#删除环境初始化
ansible-playbook k8s.yml -i env/dev -D -t init-rm
```

---

#### #8 功能解说

##### #8.1 本文常用 ansible 命令

`ansible-playbook k8s.yml -i env/dev -D -t rmi,build,deploy -e applist=app-v1`

- ansible-playbook 执行 ansible 剧本命令行
- k8s.yml 当前目录剧本文件名
- -i 指定 inventory 节点路径
- -D 是--diff 简称,显示执行过程中文件修改变化
- -t 是--tags 简称,执行 tag 标记部分,使用`,`分隔多个 tag
- -e 是--extra-vars 简称,命令行指定变量,变量优先级最高
- -C 是--check 简称,试运行,用于检测运行过程

##### #8.2 储存卷 PVE

为便于管理与维护,本实例存储卷`PVC`使用静态储存  
使用`PVC`时挂载路径添加对应服务子路径 subPath
使用 cronJob 每天压缩与清理 PVC 储存的 log 文件
储存实例类型有 NFS、阿里云 NAS、腾讯云 CFS、AWS EFS、Azure Files  
路径 roles/k8s/templates/init 前缀是`1.4.pvc`的文件

##### #8.3 日志方案(java 服务)

- 使用 log4j2 配置需要量化的 log 储存到 ElasticSearch
- 使用 log4j2 配置日志储存到文件,容器挂载 PVC
- 使用 loki 搜集终端日志,UI 界面使用 grafana

log4j2 配置在 configmap `roles/k8s/templates/jetty/configmap/`

##### #8.4 墙裂推荐的 k8s 工具软件 ！！！

> 以下部署 yaml 路径 roles/k8s/templates/init/

- 8.4.1 https 证书自动续签 `cert-manager`  
   官网 https://cert-manager.io  
   GitHub https://github.com/cert-manager/cert-manager  
   注意事项：

  1. 配置自己的 cert-ssl-issuer.yml  
  2. http 认证创建证书,需要域名解析到正确的公网IP  
  3. DNS 认证需要配置DNS解析权限,可以查看官网文档  

- 8.4.2 k8s 面板 `KubePi`
  Kubernetes 可视化面板,可管多个 k8s 集群,国产开源
   GitHub https://github.com/1Panel-dev/KubePi  
  ![](https://imgs.elvin.vip/2023/k8s_kubepi-1.jpg)

- 8.4.3 k8s面板IDE工具推荐Lens 
  官网 https://k8slens.dev
  ![](https://imgs.elvin.vip/2023/k8s_lens-1.jpg)
- 8.4.4 k8s 用户权限管理 `permission-manager`  
   添加配置用户权限,生成用户 kubeconfig 文件  
   GitHub https://github.com/sighupio/permission-manager  
  ![](https://imgs.elvin.vip/2023/k8s_permission-manager-1.jpg)

##### #8.5 有状态服务 StatefulSet

- 有状态服务使用 StatefulSet 方式部署,需要挂载 PVC 储存
- 因为有状态服务部署后很少更改,放在 init 分类,前缀有 data 的 yml 文件
- - 如 redis roles/k8s/templates/init/3.data-redis-standone.yml
- 测试环境部署单节点够用，生产环境推荐使用公有云云原生服务

##### #8.6 监控警报

**监控方案为 prometheus, 主要包含如下模块:**

- [node-exporter 采集节点指标](https://github.com/prometheus/node_exporter)
- [kube-state-metrics 汇聚容器状态指标](https://github.com/kubernetes/kube-state-metrics)
- [metrics-server 汇聚资源度量指标](https://github.com/kubernetes-sigs/metrics-server)
- [prometheus 收集和储存指标,并提供查询接口](https://github.com/prometheus/prometheus)
- [alertmanager 监控警告路由管理](https://github.com/prometheus/alertmanager)
- [grafana 仪表盘 UI 页面展示](https://github.com/grafana/grafana)
- [dingtalk 使用钉钉机器人发送警报通知](https://www.cnblogs.com/elvi/p/12210178.html)

**其它监控相关**

- [prometheus-adapter 容器自动扩容需要](https://www.cnblogs.com/elvi/p/16846454.html)

- [loki 日志储存和查询](https://github.com/grafana/loki)
- [promtail 采集日志发送给 loki](https://github.com/grafana/loki)

**监控警报规则**

prometheus 采集和警报规则都在 prometheus-config.yml 文件  
包含警报规则如下:

- k8s 节点 CPU、内存、磁盘使用率,磁盘剩余容量
- 容器 Pod 状态、CPU 和内存的限制使用率
- 其它服务如 JVM、Redis、rabbitmq

**grafana 模板**

JVM 监控 grafana 视图:  
![](https://imgs.elvin.vip/2023/k8s_grafana_jvm_v1.jpg)

##### #8.7 容器镜像仓库

> docker-registry 单独部署使用可以查看我博客  
> https://www.cnblogs.com/elvi/p/13394449.html  
> 服务部署到公有云,推荐直接使用公有云的镜像储存服务

- [docker-registry 容器镜像仓库](https://github.com/distribution/distribution)
- [docker-registry-ui 镜像查看 web 界面](https://github.com/Joxit/docker-registry-ui)

![](https://imgs.elvin.vip/2023/k8s_registry_ui2.jpg)

##### #8.8 镜像构建

- 镜像构建 + push 到镜像仓库
- 构建镜像不包含源码编译,可按需修改 dockerfile 里的下载地址
- 其它工具如 Jenkins(源码编译) -> 储存编译包 -> 镜像构建 -> 镜像仓库

配置里有 3 个镜像仓库地址(公有云分内网和外网地址)

- local_repository_url 构建默认 push 到本地镜像仓库
- push_repository_url 推送到远程镜像仓库地址
- deploy_repository_url 部署时的镜像仓库地址

##### #8.9 安全

请按需并自行解决安全问题,提示以下注意事项:

- yaml 储存节点配置访问控制
- 使用 ansible-vault 加密 ansible 密码文件
- 手动配置 kubeconfig, 并限制 k8s-apiserver 访问

##### #8.10 其它

- 由于所有部署步骤,模板均可按需更改,自由度很高
- k8s 所有配置、部署的操作,均保存 yaml 文件,便于以后升级、迁移等维护
- 若已熟悉 ansible,可使用本项目作为管理 k8s 部署服务的参考
- 做自动化部署还需结合其它工具，比如使用 Jenkins

_使用 Jenkins+ansible+钉钉通知，自动化部署通知:_  
![](https://imgs.elvin.vip/2023/k8s_deploy_notice_v1.jpg)

#### #9 日常使用命令参考

```bash
#更改构建参数后，查看dockerfile变化
ansible-playbook k8s.yml -i env/dev -D -t dockerfile -e applist=app-v1 -C

#更改部署参数后查看deployment变化
ansible-playbook k8s.yml -i env/dev -D -t yml -e applist=app-v1 -C

#单独更改configmap配置后,服务需要重启生效
ansible-playbook k8s.yml -i env/dev -D -t config,restart -e applist=app-v1

#构建和部署服务,rmi是删除构建节点已存在的相同tag镜像
ansible-playbook k8s.yml -i env/dev -D -t rmi,build,deploy -e applist=app-v1

#部署生产环境,使用upload上传镜像到外网镜像仓库
ansible-playbook k8s.yml -i env/prod -D -t upload,deploy -e applist=app-v1

#更改prometheus监控警报规则后需要reload生效
ansible-playbook k8s.yml -i dev -D -t monitor-config,monitor-reload
```

#### #10 作者  

Elvin hi@elvin.vip  
主要博客 [blog.elvin.vip](http://blog.elvin.vip)  


Source  
[https://gitee.com/alivv/ansible-app2k8s](https://gitee.com/alivv/ansible-app2k8s)  

[https://github.com/alivv/ansible-app2k8s](https://github.com/alivv/ansible-app2k8s)  

