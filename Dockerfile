FROM node:19

ENV BLOG_DIR /blog

#RUN npm install -g cnpm --registry=https://registry.npm.taobao.org
#RUN rm /usr/local/bin/npm
#RUN ln -s /usr/local/bin/cnpm /usr/local/bin/npm

#安装hexo
RUN npm install -g hexo-cli

#建立博客目录
RUN mkdir $BLOG_DIR

#利用hexo init 命令初始化博客
RUN  hexo init $BLOG_DIR
RUN  cd #BLOG_DIR && npm install




#设置git的Email和user
RUN git config --global user.name "OrezzerO"
RUN git config --global user.email "orezsilence@163.com"


#挂载博客所在的卷以及.ssh文件夹
VOLUME ["$BLOG_DIR","/root/.ssh"]

#设置工作目录
WORKDIR $BLOG_DIR

#安装hexo-deployer-git
RUN npm install hexo-deployer-git --save

#暴露4000端口
EXPOSE 4000
#设置运行镜像的默认命令
CMD ["hexo","server"]


