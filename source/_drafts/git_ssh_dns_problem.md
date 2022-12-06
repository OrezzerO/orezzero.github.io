---
title: 记一次 Github 无法使用 git 客户端的问题
date: 2022-12-06 14:26:25
categories:
- CS
- Common
tags:
- git
---

# 问题
使用 git push 代码到 github. 直接卡住了, 过了很长时间报错. 执行 `telent github.com 22`无法连通.

# 解决方案及原因

## 解决方案
将 DNS 解析服务器配置为 `8.8.8.8`.


# 原因
好在自己有另一台机器, 可以连上 github. 比对两台机器, 可以发现, 出问题的机器 github.com 域名解析出来是一个贵州的IP: `182.43.124.6`. 而没出问题的机器,解析出来的是新加坡的IP: `20.205.243.166`.
后者 telnet 结果:
```
# telnet 20.205.243.166 22
Trying 20.205.243.166...
Connected to github.com.
Escape character is '^]'.
SSH-2.0-babeld-cd305013
```
可以看到 SSH 的返回, 这是能正常连接的.

出问题的机器没有指定 DNS 服务器, 没出问题的机器指定了 8.8.8.8.
