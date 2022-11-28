---
title: 在 MacOS 上调试 JVM
date: 2022-11-23 08:15:17
categories:
- CS
- Java
tags:
- jvm
- java
---

# 背景
最近在看 JVM 源码,没有 debug 环境很不方便, 都不知道方法是怎么跳转的. 因此想要自己搭一个 debug 环境. 网上有很多相关的文章, 但毕竟不是一模一样环境, 一点小小的差异, 就可能让编译失败,浪费很多时间.

因此我选择通过 brew 的编译方式来, 稍微修改一下参数即可获得我们需要的 debug 版本 JVM.


# 环境
* Mac Studio M1 Max
* macOS Monterey 12.5.1

# 编译过程

### 尝试直接通过 brew 编译 JVM
执行命令

```shell
brew install --build-from-source --verbose openjdk@11
```
直接安装 jdk 11, 这个命令会从源码安装 openjdk11. 可以看下能不能编译成功. 如果这个命令编译不成功,后面的步骤页没必要尝试了; 如果编译成功了, 那我们就会比较有信心了.

这个命令会输出很多细节信息, 这很重要.

上述命令实际上执行的是 [openjdk@11.rb](https://github.com/Homebrew/homebrew-core/blob/master/Formula/openjdk%4011.rb), 通目录下还有 openjdk8,17,19 可供选择.


### brew 编译 JVM 的过程
1. 下载并解压源码到 `/private/tmp/openjdk11xxx`中
1. 下载并解压 boot-jvm 到 `/private/tmp/openjdk11-boot-jdkxxx` 中
3. 根据 [openjdk@11.rb](https://github.com/Homebrew/homebrew-core/blob/master/Formula/openjdk%4011.rb) 中的配置执行 configure 脚本
4. 执行 make 命令:`make images CONF=release`
5. 删除所有临时文件

为了能编译出可以 debug 的 JVM ,我们还需要做两件事情:
1. 在配置 configure 脚本时,添加 debug 参数
2. brew 在安装完成后会将源码删除, 我们需要将源码保留

### 手动编译 JVM
接下俩我们仿照brew 的编译方式手动编译 JVM:
1. 解压源码
brew 安装完成后会删除源码,但是不会删除下载下来的源码压缩包,我们可以手动解压这个压缩包,然后将源码放到我们自己的目录中.

相关的命令在 brew 编译 JVM 的输出中有,可以直接参考.

> 注意: 解压目标文件夹需要已经存在.

2. 解压 boot jdk
同上, 我们需要吧boot jdk 解压出来


3. 修改 configure 参数执行 configure 脚本
执行 configure 脚本的参数在brew 输出中也有,可以抄下来.我们需要对其中几个参数进行修改:
* `--with-boot-jdk` 如果修改了 boot-jdk 的位置,需要将这个参数指向真确的位置
* `--with-debug-level` 修改为fastdebug
* `--with-native-debug-symbols` 的值修改为 internal, 表示会把符号表嵌入到二进制中,这是 debug 的关键

configure 命令的例子
```shell
./configure --disable-hotspot-gtest --disable-warnings-as-errors --with-boot-jdk-jvmargs=-Duser.home=/Users/zhangchengxi/Library/Caches/Homebrew/java_cache --with-boot-jdk=/private/tmp/openjdkA11-20221122-35955-58bnn5/jdk11u-jdk-11.0.16.1-ga/boot-jdk --with-debug-level=fastdebug --with-conf-name=release --with-jvm-variants=server --with-jvm-features=shenandoahgc --with-native-debug-symbols=none --with-vendor-bug-url=https://github.com/Homebrew/homebrew-core/issues --with-vendor-name=Homebrew --with-vendor-url=https://github.com/Homebrew/homebrew-core/issues --with-vendor-version-string=Homebrew --with-vendor-vm-bug-url=https://github.com/Homebrew/homebrew-core/issues --without-version-opt --without-version-pre --enable-dtrace --with-sysroot=/Library/Developer/CommandLineTools/SDKs/MacOSX12.sdk --with-extra-ldflags=-Wl,-rpath,@loader_path/server -headerpad_max_install_names
```

> 这里有个问题, brew 执行这个命令是可以成功的,但是我执行的时候, 必须把最后一个参数 headerpad_max_install_names 去掉才能成功.

4. 执行 make 命令: `make images CONF=release`
这个命令会在 `release/images/jdk/`  下创建 JVM 的二进制

上述步骤完成之后, 我们就有了可以用于 debug 的 JVM 了.


### 通过 Vscode 启动 java 并 debug
我们通过 vscode 打开 jvm 源码之后, 可以在左边打开一个 debug 界面.在这个界面中有一个
`create a launch.json file` 的按钮, 我们点击它,就能创建一个 `.vscode/launch.json` 的文件.
最终这个文件会长这个样子:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "(lldb) 启动",
            "type": "cppdbg",
            "request": "launch",
            "program": "/your/path/to/jdk/source/build/release/images/jdk/bin/java",
            "args": [
            "-Dfile.encoding=UTF-8","-Djava.compiler=NONE",
            "-classpath",
            "/dir/demo/target/classes",
            "org.example.Main"],
            "stopAtEntry": true,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "externalConsole": false,
            "MIMode": "lldb",
            "targetArchitecture": "arm64"
        }
    ]
}
```

 这里面有两个参数需要修改:
 * "program": 代表你编译生成的 java 命令的路径
 * "args": 代表 java 命令的参数

 > 小tips : args 参数可以在 JAVA IDE 的输出中找到, 但需要删除其中有关 IDE 的 aggent 参数.

参考:[Customize debugging with launch.json](https://code.visualstudio.com/docs/cpp/config-clang-mac#_customize-debugging-with-launchjson)

配置完成之后, 就能开始 debug 了.


# 参考文档
[Building the JDK](https://openjdk.org/groups/build/doc/building.html)
