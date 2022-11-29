---
title: 使用 SSH 实现远程登录内网机器 (MacOS)
date: 2022-11-28 17:12:32
categories:
- CS
- Linux
tags:
- ssh
- network
- todo
---

# 背景
现在我的主力开发机器是台台式机, 有时候出门在外, 就没办法操控这台机器了. 我解决这个问题的**基本思路**是: 租用一台云上带公网域名的机器,然后将本地 22 端口映射到云服务器上. 这样就可以将云服务器作为一台跳板机,登录我本地的机器了.


# 目标
* 将本地 22 端口映射到云上机器
* 让本地机器开机运行脚本,自动完成上述工作

# 实现步骤
## 准备工作:购买一台云服务器
我买的的是一台2C4G,腾讯云服务器.趁双11+新人优惠,只要100元/年.需要获取这台机器的IP,设置 ssh 公钥,让本地机器可以通过shell**免密**登录云服务器.



## 本地机器配置
构造以下两个文件:
remote_ssh.sh:
```shell
#!/bin/bash

PORT='8888'
n=1
while true
do
  echo "try $n"
  ssh -o ExitOnForwardFailure=yes -R 8888:localhost:22 -N root@cloud_ip
  n=$((n+1))
  echo "fail $n"
  sleep 15
done
```
这个脚本会将云服务器上的 8888 收到的请求转发给本地22端口, 也就是本地 sshd 监听的端口. 同时如果操作失败,就会15s后重试.
变量说明:
* **root**: 登录云服务器的用户名,根据你的需要修改
* **cloud_ip**: 云服务器的公网ip
* **-o ExitOnForwardFailure=yes**: 设置如果端口转发开启失败就退出的选项

startup.sh:
```shell
#!/bin/bash

curday=`date +%Y-%m-%d`

nohup bash ~/git/shell/remote_ssh.sh 2>&1 >~/git/shell/logs/remote_ssh$curday.log &
```
这个脚本会执行 `remote_ssh.sh` 这个脚本,并将日志输出到`~/git/shell/logs/`文件夹中.

将`startup.sh`的默认打开方式修改为 Term 或者 iTerm.

在系统设置->用户与群组将 startup.sh 添加到登录项.


## 云上机器配置
修改 `/etc/ssh/sshd_config` 文件, 添加如下配置:
```
ClientAliveInterval 10
ClientAliveCountMax 1
```

这两个配置会开启服务端 shhd 对于客户端的探活,如果客户端连接断开了, 服务端也会关闭连接.


# 遇到的坑

## 端口转发失败之后, ssh 不退出
端口转发失败之后, ssh 不退出,就没办法做重试. 在添加 `-o ExitOnForwardFailure=yes` 选项之后,修复了这问题.

## ssh 断开之后, sshd 依然监听端口
ssh 断开之后, sshd 依然监听端口. 当 ssh 继续重试建立端口转发,因为服务端 sshd 依然占用之前那个端口,导致重试始终无法成功.
解决方案是给 sshd 开启探活,添加 ClientAliveInterval 和 ClientAliveCountMax 配置.



# 参考文档:
[SSH教程](https://wangdoc.com/ssh/port-forwarding): 阮一峰的SSH教程, 看完不需要多长时间,能对 SSH 有初步了解
[how-can-a-remote-ssh-tunnel-port-be-closed-on-the-ssh-server-when-the-ssh-comman](https://superuser.com/questions/1563605/how-can-a-remote-ssh-tunnel-port-be-closed-on-the-ssh-server-when-the-ssh-comman)
[man:sshd_config](https://man.openbsd.org/sshd_config)
