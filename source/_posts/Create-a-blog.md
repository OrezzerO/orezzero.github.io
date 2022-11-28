---
title: 创建一个自己的博客
date: 2022-11-23 06:55:58
updated: 2022-11-28 16:37:53
categories:
- CS
- Blog
tags:
- hexo
- NexT
---

# 背景
几年前就搭建了自己的 Github Page, 但当时搭建的时候, 博客文章没有上传到 Github, 只上传了生成的静态文件,而且没有自动部署的能力.准备重新提笔写博客,就重新搭一套.

# 目标
这次搭博客有如下技术目标:
1. 搭建完成之后,只依赖 **文本编辑**+**git** 就能完成写作, 不需要其他依赖(尤其是node依赖)
2. 文本内容上传 Github 之后**自动部署**.
3. 任何其他人能够方便复刻这一套方案.


# 快速复刻本项目
## 创建站点
如果你也想搭建一套博客,而不想折腾环境,可以直接 Fork [本项目](https://github.com/orezzero/orezzero.github.io),然后改名为 username.github.io  ，username 是你在 GitHub 上的使用者名称.
具体步骤为:
1. Fork 本项目,fork 时可以将 orezzero.github.io 改为 username.github.io  ，username 是你在 GitHub 上的使用者名称.
2. 进入你的仓库, 进入 Action 页面, 确认 Action 功能已经被启用
3. 删除 `source/_posts` (这里面是我的文章) 除了 template.md 的文件,删除 `sources/images/`中的图片, 修改 `source/about/index.md` 然后提交代码
4. 等待 Action 完成 (第一次跑pages build and deployment会失败,别管他)
5. 在你的仓库中进入 Settings > Pages > Source，并将 branch 改为 gh-pages。(在第一次提交代码之前,这个配置无法修改)
6. 手动触发 Action 中的 Pages action 或者提交一个修改触发 Action,等待 Action 完成
7. 访问 username.github.io 就能看到你的站点了

[https://easyit-blog.github.io/](https://easyit-blog.github.io/) 就是这么创建出来的.

> 本项目有一些区别于原生 Next 主题的定制化配置, 可以参考 [PR Modify theme settings #1](https://github.com/OrezzerO/orezzero.github.io/pull/1) 来自定义你的主题.


## 写作
在 `source/_posts` 文件夹中创建 markdown 文件. Hexo 对于 md 的格式有一定要求,需要用这种格式开头:
```
---
title: 创建一个自己的博客
date: 2022-11-23 06:55:58
tags:
---
```

这个头部后面就可以书写正文了.


# 技术细节

## 如何从零开始搭建 Hexo
我使用了 Docker 来初始化项目. 首先我通过 [Dockerfile](https://github.com/OrezzerO/orezzero.github.io/blob/main/Dockerfile) 创建了一个 Hexo 镜像, 启动这个镜像就会构建 Hexo 的基本环境到 /blog 目录下. 然后我将容器中的 /blog 目录拷贝出来. 基本环境就搭建好了.
```shell
# 构建 docker 镜像
docker build -t hexo .
```

```shell
# 启动 docker 容器
docker run --name hexo -d  -P hexo
```

```shell
## 拷贝
docker cp hexo:/blog ./
```


## 本地启动 Hexo Server
按上节构造好镜像之后, 使用 docker-compose 配置文件启动 docker-compose 即可.

> 需要将配置文件放在 hexo 目录, 并在这个目录执行 docker compose 命令.


```shell
# 启动 docker compose
docker-compose up -d
```

```shell
# 关闭 docker compose
docker-compose down
```


## 自动部署
自动部署完全照搬了官网的 [在 GitHub Pages 上部署 Hexo](https://hexo.io/zh-cn/docs/github-pages) 十分简单.

> 自动部署在网上有很多教程, 但是这些教程都没有官网的简单可靠.

## 遇到的坑
1. 主题文件夹`themes/next`没能成功上传到 github 上,导致编译不出静态页面.


# 参考文档
[Next 主题文档站](https://theme-next.js.org/docs/getting-started/): 这个网站比较重要,很多配置可以参考这里的文档.
[Hexo 官网](https://hexo.io/zh-cn/)
[在 GitHub Pages 上部署 Hexo](https://hexo.io/zh-cn/docs/github-pages)
[建站](https://hexo.io/zh-cn/docs/setup)
