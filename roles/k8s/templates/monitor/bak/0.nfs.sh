
#NFS 服务端
mkdir -p /data/k8s
echo "/data/nfs *(rw,no_root_squash,sync)">>/etc/exports

#centos
# yum install nfs-utils rpcbind -y
# systemctl enable rpcbind nfs-server
# systemctl restart rpcbind nfs-server

#ubuntu 服务端
apt install nfs-kernel-server nfs-common -y
service nfs-kernel-server restart

exportfs -r
showmount -e localhost

#NFS客户端（所有node）
# yum install nfs-utils -y
# systemctl enable --now rpcbind
#ubuntu 客户端
# apt install nfs-common -y
