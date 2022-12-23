---
title: SkyWalking-java 简介
date: 2022-12-19 16:29:59
categories:
- CS
- Java
tags:
- skywalking
- trace
---


# 背景
最近在调研跨线程 trace, 调研了跨线程 skywalking-java (skywalking 的 java 客户端) 的跨线程 trace 实现.

本文的内容包括:
1. skywalking-java api 的简单使用
2. skywalking-java api 重要概念及对应的实现
3. skywalking-java 跨线程 trace 是如何实现的
4. skywalking 的瓶颈以及我遇到的问题.


前置知识:


# Skywalking-java api 的简单使用

## 普通用户API
官方文档中 [Tracing APIs](https://skywalking.apache.org/docs/skywalking-java/v8.13.0/en/setup/service-agent/java-agent/application-toolkit-trace/) 一节中有用户API详细的说明. 简单来说,加一个 `@Tracer` 注解就能完成一般用户的需求:
```java
@Trace
public User methodYouWantToTrace(String param1, String param2) {
    // ActiveSpan.setOperationName("Customize your own operation name, if this is an entry span, this would be an endpoint name");
    // ...
}
```


## 中间件用户 API
对于普通用户来说,上面这个接口已经够用了, 但对于中间件用户来说, 要需要深入看下非切面的API:

### Span 分类
[Skywlking 中将 Span 分为三类](https://skywalking.apache.org/docs/skywalking-java/v8.13.0/en/setup/service-agent/java-agent/java-plugin-development-guide/) :

1. **EntrySpan**: 代表一个服务提供者.
2. **LocalSpan**: 代表一个普通方法.注意,它既不代表一个服务提供者, 也不代表服务消费者.
3. **ExitSpan**: 代表一份服务消费者

创建上面三个 Span 的方法分别为 [ContextManager.java](https://github.com/apache/skywalking-java/blob/main/apm-sniffer/apm-agent-core/src/main/java/org/apache/skywalking/apm/agent/core/context/ContextManager.java) 中的:

```java
public static AbstractSpan createEntrySpan(String endpointName, ContextCarrier carrier)
public static AbstractSpan createLocalSpan(String endpointName)
public static AbstractSpan createExitSpan(String endpointName, ContextCarrier carrier, String remotePeer)
```

> 上文中 `@Tracer` 注解生成的就是 LocalSpan


### 跨应用传递
APM 需要将不同应用间的 Span 串联起来, 通常来说是在请求中加上 APM 相关的信息来实现的.
Skywalking 的实现直接看官方文档 [ContextCarrier](https://skywalking.apache.org/docs/skywalking-java/v8.13.0/en/setup/service-agent/java-agent/java-plugin-development-guide/#contextcarrier)

### Span 的操作
可以通过 [AbstractSpan 接口](https://skywalking.apache.org/docs/skywalking-java/v8.13.0/en/setup/service-agent/java-agent/java-plugin-development-guide/#abstractspan) 来操作 Span ,向其中添加信息. 可以通过 [Async Span APIs](https://skywalking.apache.org/docs/skywalking-java/v8.13.0/en/setup/service-agent/java-agent/java-plugin-development-guide/#abstractspan) 来操控异步 Span.


### 举个例子
SkyWalking-java 使用 java agent 在运行时动态修改字节码来做到埋点的注入. 不同的中间件需要实现一个 SkyWalking 插件才能接入. 这部分内容可以参考 [Byte Buddy Agent 初探--以 SkyWalking-java 为例](https://orezzero.github.io/2022/12/08/bytebuddy_agent_skywalking/) 中 SkyWalking-java 简要分析 一节.

客户端埋点代码包含如下逻辑:
1. 获取请求信息
2. 构造 ExitSpan
3. 向请求中注入 SkyWalking header

服务端包含如下逻辑:
1. 获取请求信息
2. 构造 EntrySpan
3. 向请求中的 SkyWalking header 提取出来, 注入到本地的 `ContextCarrier` 中


可以参考这两个文件: [SOFA RPC 客户端埋点](https://github.com/apache/skywalking-java/blob/main/apm-sniffer/apm-sdk-plugin/sofarpc-plugin/src/main/java/org/apache/skywalking/apm/plugin/sofarpc/SofaRpcConsumerInterceptor.java) 和 [SOFA RPC 服务端埋点](https://github.com/apache/skywalking-java/blob/main/apm-sniffer/apm-sdk-plugin/sofarpc-plugin/src/main/java/org/apache/skywalking/apm/plugin/sofarpc/SofaRpcProviderInterceptor.java)


# skywalking-java api 重要概念及对应的实现

## Trace 相关概念
[Trace Data Protocol v3 ](https://skywalking.apache.org/docs/main/v9.2.0/en/protocols/trace-data-protocol-v3/) 描述了SkyWalking 客户端和服务端之间的通信协议. 其中将链路追踪划分为三个层次:
1. Trace: 代表整个链路
2. Segment: 代表一个进程(应用)中所有的 Span 集合
3. Span: 代表一个操作,比如读取一次DB

分别看下这三个对象的唯一标识是怎么产生的, 就能比较好理解他们分别代表什么维度:

**Trace Id** <br/>
Trace Id 通过 `GlobalIdGenerator.generate()` 产生,包含三个部分:

1. PROCESS_ID: 代表应用程序实例 ID
2. `Thread.currentThread().getId()`: 代表线程 ID
3. THREAD_ID_SEQUENCE: 包含两个部分 1) 以毫秒记的时间戳 2) 线程级别的 0 到 9999 的序号


可以看出, Trace Id 是 实例维度+线程维度+毫秒维度+序号维度 组成的.

**注意**: Trace Id 是会通过请求传递到上游服务的,如果下游传递了 Trace Id 给上游, 上游会继续使用这个 Trace Id

**Segment Id** <br/>
Segment Id 的生成算法和 Trace Id 是一样的.

**Span Id** <br/>
SpanId 是一个在 `TracingContext` 中维护的,从 0 开始的序列.

注意: 这里的 `TracingContext` 是一个 ThreadLocal 变量, 生命周期和一个 Segment 想通.


## 实现
**一些类和数据结构**
1. **Span**: 保存了 spanId,parentSpanId,tags 等标签, 用来表示一个操作.
2. **Segment**: 保存了 traceSegmentId,relatedGlobalTraceId, Span 数组 等信息, 用来表示一组同线程同 traceId 的 Span 集合
3. **TracingContext**: 用来操作 Segment 和 Span 的工具类,持有 TraceSegment 引用, 维护了一个 `List<Span>`  表示的栈. TracingContext 和单个线程对应, 单个TracingContext中只保存该线程对应的 Segment 和 Span.
4. **ContextManager**: TracingContext 的控制类, 持有 TracingContext 的 ThreadLocal 引用. ContextManager 中的静态方法会

这是一个比较简单模式: 用户使用 `ContextManager` 来控制 `TracingContext`. `TracingContext` 来生成 `Segment` 和 `Span` 对象, 并将他们组合到一起.

<!-- todo 看看要不要举个例子 -->


# 跨线程 Trace 的实现
跨线程Trace 分为两种情况:
1. 单个 Span 跨线程. 也就是说, 同一个Span 的 `start` 和 `stop` 操作在不同的线程中
2. 整体 Trace 跨线程. 也就是说"父子Span"在不同的线程中.

我们分别讨论这两种情况.

## 单 Span 跨线程
单 Span 跨线程是指同一个Span 的 `start` 和 `stop` 操作在不同的线程中. 直接上代码:

```java
public class Main {
    public static void main(String[] args) {
        AbstractSpan mySpan = ContextManager.createEntrySpan("mySpan");
        Runnable runnable = () -> {
            try {
                TimeUnit.SECONDS.sleep(1);
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
            // 3. Propagate the span to any other thread.
            // 4. Once the above steps are all set, call #asyncFinish in any thread.
            mySpan.asyncFinish();


        };
        // 1. Call #prepareForAsync in the original context.
        mySpan.prepareForAsync();
        new Thread(runnable).start();
        // 2. Run ContextManager#stopSpan in the original context when your job in the current thread is complete.
        ContextManager.stopSpan();
    }
}
```

上面这段代码, 在Main线程中创建了了一个 Span ,但在子线程中才结束这个 Span. 整个过程如下:


### 原理
整个单 Span 跨线程的过程分为四个阶段,我们分别分析:

#### 在原始上下文中调用 prepareForAsync 方法
`prepareForAsync` 方法是 Span 的方法. 它会标记这个 Span 处于异步模式, 同时在方法内部调用 `ContextManager#awaitFinishAsync` 方法. 上下文中会通过`asyncSpanCounter`字段记录当前上下文有多少 Span 处于异步模式中.

#### 在原始方法中调用 stopSpan 方法
由于上一步调用了 `prepareForAsync`, `stopSpan` 方法不会直接结束,而是**先**判断当前上下文中**asyncSpanCounter**是否为0.为0的话结束,非0的话不结束.


#### 将 Span 对象传递到其他线程中
可以使用闭包传递,这很好理解,不做说明了.

### 在子线程中嗲用 asyncFinish
调用 asyncFinish 会通知该 Span 的上下文, 减少`asyncSpanCounter`数量.并且再次尝试结束Span,如果此时**asyncSpanCounter**为0,就结束Span,否则不结束.

### 总结
在单个 Span 跨线程的场景下, 跨线程的 Span 还是原来的对象, 它持有原来线程 `Context` 的引用, traceId 等相关信息都没有发生改变.


## 整体 Trace 跨线程
整体 Trace 跨线程是说"父子Span"在不同的线程中.我们直接看代码:

```java
public class Main2 {

    public static void main(String[] args) {
        AbstractSpan mySpan = ContextManager.createExitSpan("parent", "childThread");

        Runnable runnable = () -> {
            try {
                TimeUnit.SECONDS.sleep(1);
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
        };
        new Thread(new RunnableWrapper(runnable)).start();
        ContextManager.stopSpan(mySpan);
    }

    static class RunnableWrapper implements Runnable, EnhancedInstance {

        private Object skyWalkingDynamicField;
        private Runnable runnable;

        public RunnableWrapper(Runnable runnable) {
            if (ContextManager.isActive()) {
                setSkyWalkingDynamicField(ContextManager.capture());
            }
            this.runnable = runnable;
        }

        @Override
        public void run() {
            AbstractSpan span = ContextManager.createLocalSpan("runnable.run");
            span.setComponent(ComponentsDefine.JDK_THREADING);

            final Object storedField = getSkyWalkingDynamicField();
            if (storedField != null) {
                final ContextSnapshot contextSnapshot = (ContextSnapshot) storedField;
                ContextManager.continued(contextSnapshot);
            }
            try {
                runnable.run();
            } finally {
                ContextManager.stopSpan();
            }
        }

        @Override
        public Object getSkyWalkingDynamicField() {
            return skyWalkingDynamicField;
        }

        @Override
        public void setSkyWalkingDynamicField(Object value) {
            this.skyWalkingDynamicField = value;
        }
    }

}
```

这段代码是将`RunnableInstrumentation` 的代码增强逻辑展开后得来的(有简化).整体 Trace 跨线程主有两个主要步骤:
1. 创建 RunnableWrapper 对象的时候, 在**构造函数**中,将当前线程的 `ContextSnapshot` 设置到 RunnableWrapper 的 skyWalkingDynamicField对象中.
2. 在子线程执行 `run` 方法时, 创建一个新的 `Span`, 并将父线程的 `contextSnapshot` 当做参数传递给 `continued` 方法.

ContextSnapshot 的构造如下:
```java
    @Override
    public ContextSnapshot capture() {
        ContextSnapshot snapshot = new ContextSnapshot(
            segment.getTraceSegmentId(),  // segmentId
            activeSpan().getSpanId(),     // spanId
            getPrimaryTraceId(),          // traceId
            primaryEndpoint.getName(),    // parentEndpoint
            this.correlationContext,     
            this.extensionContext
        );
        return snapshot;
    }
```

`continued` 方法如下:
```java
/**
 * Continue the context from the given snapshot of parent thread.
 *
 * @param snapshot from {@link #capture()} in the parent thread. Ref to {@link AbstractTracerContext#continued(ContextSnapshot)}
 */
@Override
public void continued(ContextSnapshot snapshot) {
    if (snapshot.isValid()) {
        TraceSegmentRef segmentRef = new TraceSegmentRef(snapshot);
        this.segment.ref(segmentRef);
        this.activeSpan().ref(segmentRef);
        this.segment.relatedGlobalTrace(snapshot.getTraceId());
        this.correlationContext.continued(snapshot);
        this.extensionContext.continued(snapshot);
        this.extensionContext.handle(this.activeSpan());
    }
}
```

`continued` 方法通过 `ContextSnapshot` 构造 `TraceSegmentRef`,让当前线程的 Segment 和 Span 引用到 `TraceSegmentRef`, 从而建立起了两个线程的联系. 当这两个线程的 Segment 都完成之后, 就会被发送到 SkyWalking 服务端, 服务端可以根据这两个 Segment 之间的关系建立起联系.

# 我遇到的问题
我再做一个精细化耗时分析的程序,它可以实现跨线程的精细化耗时分析. 举个RPC的例子: 它会记录 IO 线程中, 请求到达的时间/IO 线程处理完成请求的时间; 然后将这些数据传递给业务线程, 业务线程继续记录 RPC 内部处理时间, 业务耗时等.

现在遇到的**问题**是:  在多层线程池嵌套的场景, 如何确定这个 Trace 的结束时间?

想象这么一个场景:
调用一个 RPC 接口, 这个 RPC 接口会再另外开启 5 条线程执行批量数据库操作,然后不等待数据库操作返会结果, RPC 提前返会.

在这种场景下,供涉及七条线程: IO 线程, RPC 业务线程, 批量操作5条线程.这七条线程只知道自己的 Span 状态, 无法得知其他 Span 的状态, 也就没办法知道整个事务什么时候结束(本线程事务结束的时候, 并不清楚其他线程的事务是否结束).

对于 SkyWalking, 它没有纠结整体事务有没有结束. 每个线程只关心自己的 Segment 是否结束, 结束就上报给 SkyWalking 服务端. 在上面这个例子中, 这七条线程的 Segment 是有关系的, skyWalking 可以根据这些关系, 再将他们组合起来, 统一展示.



# 参考文档
https://opentracing.io/specification/
