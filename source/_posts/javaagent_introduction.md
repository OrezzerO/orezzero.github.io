---
title: Java Agent 原理简介
date: 2022-11-24 15:02:39
categories:
- CS
- Java
- javaagent
tags:
- java
- javaagent
---

# Java Agent 是什么
Java Agent 是一种可以动态修改 Java 类字节码的技术.

使用 Java Agent 通常是为了动态增加应用的功能,但这些功能和主体业务逻辑是不耦合的, 比如说各种监控\诊断工具,甚至有公司拿它来实现 Service Mesh.
举两个例子:
1. [SkyWalking-java](https://github.com/apache/skywalking-java) SkyWalking 社区推出的 Java Agent, 用于Java 应用快速接入 SkyWalking
2. [Arthas](https://github.com/alibaba/arthas) 是 Alibaba 推出的 Java 诊断工具.
3. 阿里云 [Spring Cloud 应用 Proxyless Mesh 模式探索与实践](https://mp.weixin.qq.com/s/HjQUvTlAXuI3y_azlSh2Pw)

上面两者均是基于 Java Agent 实现的.

使用 Java Agent 可以实现如下技术目标:
1. 对源代码**无侵入**的情况下, 完成功能的添加: SkyWalking-java 主要利用这一特性, 当我们有很多系统都需要接入监控埋点时, 就不需要升级每一个应用了, 添加 Java Agent 即可.
2. **运行时动态**修改功能,实现热部署. Arthas 主要利用这一特性, Arths 的诊断功能是对性能有影响的,只能单独选择一两台服务器开启. 并且故障诊断需要故障现场,不能重启应用, 因此热部署特性对于 Arthas 来说就至关重要了.


# Java Agent 工作原理简介
## Java Agent 的启动
Java Agent 的启动有两种方式:
1. 在启动 Java 应用时,在 JVM 参数中添加 `-javaagent:/path/to/your_agent_name.jar`.下文简称 JVM 参数方式.
2. 在运行时,通过 com.sun.tools.attach.VirtualMachine#loadAgent(java.lang.String) 动态加载 Java Agent. 下文简称运行时方式.

> 这里具体说明下运行时方式的启动: 假设我们有一个 biz.jar 是我们的业务应用,  agent.jar 是我们的 Java Agent. 我们可以在启动一个 attach.jar ,来将 agent.jar  attach 到 biz.jar 上, 整个过程是不需要修改 biz.jar 的.

下面我们会从几个方面来比较这两种启动方式:


|                | JVM 参数方式     | 运行时方式          |
| :------------- | :------------- | :----------------- |
| 启动时机        | main函数执行之前  | 应用运行时          |
| 执行线程        | main 线程       | AttachListener 线程 |
| 入口函数        | premain()       | agentmain()        |
| ClassLoader    | AppClassLoader | AppClassLoader     |


### Java Agent 启动代码分析
在 JVM 接收到相关的参数之后, 就会调用 InstrumentationImpl 对象执行 agent 逻辑. JVM 方式会调用 InstrumentationImpl 的 loadClassAndCallPremain 方法, 运行时方式会调用 loadClassAndCallAgentmain 方法.这两个方法底层都是调用  loadClassAndStartAgent 方法:  

``` java
// WARNING: the native code knows the name & signature of this method
private void
loadClassAndCallPremain(    String  classname,
                            String  optionsString)
        throws Throwable {

    loadClassAndStartAgent( classname, "premain", optionsString );
}


// WARNING: the native code knows the name & signature of this method
private void
loadClassAndCallAgentmain(  String  classname,
                            String  optionsString)
        throws Throwable {

    loadClassAndStartAgent( classname, "agentmain", optionsString );
}
```

在 loadClassAndStartAgent 方法中, 首先获取 AppClassLoader ,然后通过 AppClassLoader 加载 AgentClass 类.最后通过反射调用 premain 或者 agentmain 方法.

因此我们可以得出一个结论: **除了上文表格中的不同点, JVM 方式 和 运行时方式启动的 Java Agent 没什么区别.**


agentmain 和 premain 有一个参数是 Instrumentation , Instrumentationimpl 会将自身传递给 agentmain/premian 方法.


## 实现字节码修改 -- Instrumentation 简介
Instrumentation 是 agentmain/premain 的入参, 通过这个类, 可以实现字节码修改.

Instrumentation 对于字节码的修改,可以分为两种形式:
1. transform: 修改字节码,会在字节码里面掺私货.给类加切面用这种方式.
2. redefine: 重新定义字节码, 推倒重来. 直接修改类的业务逻辑用这种方式.

redeine 是 java1.5 引入的, 而 transform 是 java 1.6 引入的. transform 的使用更方便,因此我推荐使用 transform 而不用使用 redeine.

transform 又分为两类:
1. transform: 在类第一次加载时执行
2. retransform: 调用 Instrumentation 的 retransformClasses 方法手动执行.


### transform 方法
我们可以向 `Instrumentation` 中注册 `Transformer`, 当一个类被加载或者被调用 `retransform` 时, Transformer 的 `transform` 方法会被调用. `transform` 接收一个用来表示 classFile 的二进制数组, 同时返回一个新的表示类的二进制数组.

可以用 ASM ,ByteBuddy 等框架来读取,修改这个二进制数组并返回. 这样, 一次代码增强就完成了
