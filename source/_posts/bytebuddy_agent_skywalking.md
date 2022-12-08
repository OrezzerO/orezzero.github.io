---
title: Byte Buddy Agent 初探--以 SkyWalking-java 为例
date: 2022-12-08 12:08:24
categories:
- CS
- Java
- javaagent
tags:
- java
- javaagent
- ByteBuddy
- SkyWalking
---

# 背景
byte-buddy-agent 是 ByteBuddy 的一个组件, 用于快速构建出一个 JavaAgent. SkyWalking-java 是一个 SkyWalking 为 Java 准备的运行时代码生成器, 适配了众多中间件以提供定制的监控能力.

SkyWalking-java 本质是一个 java agent ,并在其中使用了 byte-buddy-agent.

本文会介绍 SkyWalking-agent 如何使用 byte-buddy-agent 来做到代码增强的.


# ByteBuddy 基础用法
在深入 SkyWalking-agent 和 byte-buddy-agent 之前, 我们先来看下 ByteBuddy 是如何在调用一个方法前后插入日志的.

```java
class MemoryDatabase {
  public List<String> load(String info) {
    return Arrays.asList(info + ": foo", info + ": bar");
  }
}

class LoggerInterceptor {
  public static List<String> log(@SuperCall Callable<List<String>> zuper) // SuperCall 注解用于表示 zuper 是原始方法的调用.
      throws Exception {
    System.out.println("Calling database");
    try {
      return zuper.call();
    } finally {
      System.out.println("Returned from database");
    }
  }
}

MemoryDatabase loggingDatabase = new ByteBuddy()
  .subclass(MemoryDatabase.class) // 被增强的类继承于 MemoryDatabase 类
  .method(named("load")) // 被增强的方法名为 load
  .intercept(MethodDelegation.to(LoggerInterceptor.class)) // 增强方式是将方法调用代理到 LoggerInterceptor
  .make() // 构造出上述配置产生的类的字节码
  .load(getClass().getClassLoader()) // 将上述配置产生的类用过 getClass().getClassLoader() 加载到 jvm 中
  .getLoaded() // 获取已经加载的 Class 类对象
  .newInstance(); // 通过默认构造函数构造新的对象.
```

上面是一个简单的 ByteBuddy 例子. 它增强了 MemoryDatabase 类, 会在调用 MemoryDatabase.load 前后,打印输出一些信息.
ByteBuddy API 每行代码的含义都已经写在注释中了. 可以想象, 在SkyWalking agent 中, 也是构造了类似的代码增强, 在调用前后加入了 SkyWalking 埋点.

# SkyWalking-java 简要分析
我们会先分析中间件如何接入 SkyWalking-java , 然后分析 SkyWalking-java 如何接入 byte-buddy-agent.

## 插件定义
SkyWalking-java 提供了一种比较简单的 API ,来供中间件接入. 我们以 SOFA RPC 为例子看下.

一个埋点的接入代码只有两个类,以及一个配置文件,直接上代码:

[SofaRpcConsumerInstrumentation.java:](https://github.com/apache/skywalking-java/blob/main/apm-sniffer/apm-sdk-plugin/sofarpc-plugin/src/main/java/org/apache/skywalking/apm/plugin/sofarpc/SofaRpcConsumerInstrumentation.java)
```java
public class SofaRpcConsumerInstrumentation extends ClassInstanceMethodsEnhancePluginDefine {

    private static final String ENHANCE_CLASS = "com.alipay.sofa.rpc.filter.ConsumerInvoker";
    private static final String INTERCEPT_CLASS = "org.apache.skywalking.apm.plugin.sofarpc.SofaRpcConsumerInterceptor";

    @Override
    protected ClassMatch enhanceClass() {
        return NameMatch.byName(ENHANCE_CLASS);
    }

    @Override
    public ConstructorInterceptPoint[] getConstructorsInterceptPoints() {
        return null;
    }

    @Override
    public InstanceMethodsInterceptPoint[] getInstanceMethodsInterceptPoints() {
        return new InstanceMethodsInterceptPoint[] {
            new InstanceMethodsInterceptPoint() {
                @Override
                public ElementMatcher<MethodDescription> getMethodsMatcher() {
                    return named("invoke");
                }

                @Override
                public String getMethodsInterceptor() {
                    return INTERCEPT_CLASS;
                }

                @Override
                public boolean isOverrideArgs() {
                    return false;
                }
            }
        };
    }
}
```
SofaRpcConsumerInstrumentation 继承了 ClassInstanceMethodsEnhancePluginDefine ,定义了 SOFA RPC 插件如何工作,它通过接口指定了三个属性:
1. enhanceClass: 需要增强哪个类, 这里是增强 `com.alipay.sofa.rpc.filter.ConsumerInvoker`
2. getConstructorsInterceptPoints: 指定构造函数如何增强: 这个插件不需要构造函数增强
3. getInstanceMethodsInterceptPoints: 指定方法如何增强, 这里返回了一个 `InstanceMethodsInterceptPoint` 数组, 数组中每个元素代表一个增强点


接着我们看下 `InstanceMethodsInterceptPoint` 是怎么定义的:
* getMethodsMatcher: 指定了如何找到需要增强的方法, 这里指定的是名为 `invoke` 的方法
* getMethodsInterceptor: 指定如何增强刚刚指定的`invoke`方法, 这里指定的是 `org.apache.skywalking.apm.plugin.sofarpc.SofaRpcConsumerInterceptor`类, 这个类下文会分析.
* isOverrideArgs: 这个属性指定了是否需要修改修改 `invoke` 的入参,这个例子中我们不需要修改,所以返回 `false`


[SofaRpcConsumerInterceptor.java:](https://github.com/apache/skywalking-java/blob/main/apm-sniffer/apm-sdk-plugin/sofarpc-plugin/src/main/java/org/apache/skywalking/apm/plugin/sofarpc/SofaRpcConsumerInterceptor.java)
```java
public class SofaRpcConsumerInterceptor implements InstanceMethodsAroundInterceptor {

    public static final String SKYWALKING_PREFIX = "skywalking.";

    @Override
    public void beforeMethod(EnhancedInstance objInst, Method method, Object[] allArguments, Class<?>[] argumentsTypes,
                             MethodInterceptResult result) throws Throwable {
        // 省略一些代码
        final ContextCarrier contextCarrier = new ContextCarrier();
        final String operationName = generateOperationName(providerInfo, sofaRequest);
        AbstractSpan span = ContextManager.createExitSpan(operationName, contextCarrier, host + ":" + port);
        span.setComponent(ComponentsDefine.SOFARPC);
        SpanLayer.asRPCFramework(span);
    }

    @Override
    public Object afterMethod(EnhancedInstance objInst, Method method, Object[] allArguments, Class<?>[] argumentsTypes,
                              Object ret) throws Throwable {
        SofaResponse result = (SofaResponse) ret;
        if (result != null && result.isError()) {
            dealException((Throwable) result.getAppResponse());
        }

        ContextManager.stopSpan();
        return ret;
    }

    @Override
    public void handleMethodException(EnhancedInstance objInst, Method method, Object[] allArguments,
                                      Class<?>[] argumentsTypes, Throwable t) {
        dealException(t);
    }
}
```
`SofaRpcConsumerInterceptor` 会重载三个方法, 分别在 `com.alipay.sofa.rpc.filter.ConsumerInvoker#invoke()` 调用之前,之后,以及发生异常时被回调.

配置文件为:
[skywalking-plugin.def](https://github.com/apache/skywalking-java/blob/main/apm-sniffer/apm-sdk-plugin/sofarpc-plugin/src/main/resources/skywalking-plugin.def)
```def
sofarpc=org.apache.skywalking.apm.plugin.sofarpc.SofaRpcConsumerInstrumentation
```
这里面配置了 `SofaRpcConsumerInstrumentation` 类.


## 适配 ByteBuddy
通过上文的配文件,SkyWalking-java 可以获取到所有的 PluginDefine 类. SkyWalking-java 会加载这些类, 并将他们统一交给 `PluginFinder` 管理.

`PluginFinder` 的 `buildMatch()` 方法生成一个 ElementMatcher 来匹配到所有需要被加载的类型. 以 SOFA RPC 为例就是 `com.alipay.sofa.rpc.filter.ConsumerInvoker` 类.


`PluginFinder` 会被传递给 `org.apache.skywalking.apm.agent.SkyWalkingAgent.Transformer` 来构造一个 `AgentBuilder.Transformer`. 可以被上面 ElementMatcher 匹配的类,都会被 Transformer 增强.

增强逻辑如下:
* 处理每个匹配 ElementMatcher 的类
* 通过 `PluginFinder` 找到这个类对应的 `PluginDefine`
* 调用 `PluginDefine` 的 `define` 方法对方法进行增强:
  * 获取 `PluginDefine` 定义的 `InstanceMethodsInterceptPoints`
  * 遍历 `InstanceMethodsInterceptPoints`, 通过 `MethodsMatcher` 确定需要增强的方法, 通过 `getMethodsInterceptor` 获取如何增强方法. 并将 Interceptor 注入到 `InstMethodsInter` 中.
  * 将 `MethodsMatcher` 和 `InstMethodsInter` 传递给 ByteBuddy 就完成了 JavaAgent 的配置.

下面我们看下 `InstMethodsInter` 是什么:


```java
public class InstMethodsInter {
    private static final ILog LOGGER = LogManager.getLogger(InstMethodsInter.class);

    /**
     * An {@link InstanceMethodsAroundInterceptor} This name should only stay in {@link String}, the real {@link Class}
     * type will trigger classloader failure. If you want to know more, please check on books about Classloader or
     * Classloader appointment mechanism.
     */
    private InstanceMethodsAroundInterceptor interceptor;

    /**
     * @param instanceMethodsAroundInterceptorClassName class full name.
     */
    public InstMethodsInter(String instanceMethodsAroundInterceptorClassName, ClassLoader classLoader) {
        try {
            interceptor = InterceptorInstanceLoader.load(instanceMethodsAroundInterceptorClassName, classLoader);
        } catch (Throwable t) {
            throw new PluginException("Can't create InstanceMethodsAroundInterceptor.", t);
        }
    }

    /**
     * Intercept the target instance method.
     *
     * @param obj          target class instance.
     * @param allArguments all method arguments
     * @param method       method description.
     * @param zuper        the origin call ref.
     * @return the return value of target instance method.
     * @throws Exception only throw exception because of zuper.call() or unexpected exception in sky-walking ( This is a
     *                   bug, if anything triggers this condition ).
     */
    @RuntimeType
    public Object intercept(@This Object obj, @AllArguments Object[] allArguments, @SuperCall Callable<?> zuper,
        @Origin Method method) throws Throwable {
        EnhancedInstance targetObject = (EnhancedInstance) obj;

        MethodInterceptResult result = new MethodInterceptResult();
        try {
            interceptor.beforeMethod(targetObject, method, allArguments, method.getParameterTypes(), result);
        } catch (Throwable t) {
            LOGGER.error(t, "class[{}] before method[{}] intercept failure", obj.getClass(), method.getName());
        }

        Object ret = null;
        try {
            if (!result.isContinue()) {
                ret = result._ret();
            } else {
                ret = zuper.call();
            }
        } catch (Throwable t) {
            try {
                interceptor.handleMethodException(targetObject, method, allArguments, method.getParameterTypes(), t);
            } catch (Throwable t2) {
                LOGGER.error(t2, "class[{}] handle method[{}] exception failure", obj.getClass(), method.getName());
            }
            throw t;
        } finally {
            try {
                ret = interceptor.afterMethod(targetObject, method, allArguments, method.getParameterTypes(), ret);
            } catch (Throwable t) {
                LOGGER.error(t, "class[{}] after method[{}] intercept failure", obj.getClass(), method.getName());
            }
        }
        return ret;
    }
}
```


`InstMethodsInter` 与上文 *ByteBuddy 基础用法* 中的 `LoggerInterceptor` 是同一类型的东西, ByteBuddy 会将需要增强的类代理给 `intercept` 方法. 可以看 `intercept` 方法的参数上都带上了 `ByteBuddy` 的注解:
* **This**: 代表当前代理类的实例
* **AllArguments**: 原始调用的参数列表
* **SuperCall**: 代表原始调用
* **Origin**: 代表原始方法

通过 `InstMethodsInter` , SkyWalking-java 在需要增强的方法前后及异常处理阶段增加了一些回调, 回调给 `PluginDefine` 中定义的 `Interceptor`.




# ByteBuddy Agent  原理简介

在开始社介绍 ByteBuddy 原理之前, 可以先看下 [Java Agent 原理简介](/2022/11/24/javaagent_introduction/) 来回顾下原生 javaagent 是怎么工作的:

我们向 `Instrumentation` 注册一些 `Transformer`,在类加载期间 `Transformer` 的 `transform` 方法就会被调用. `transform` 方法会修改类的二进制表示(字节码), 从而实现类增强.


那么 ByteBuddy 是如何适配原生 javaagent 这种模式的呢?

ByteBuddy 内部有一个适配器 `net.bytebuddy.agent.builder.AgentBuilder.Default.ExecutingTransformer` 将原生 transform 方法适配到 `net.bytebuddy.agent.builder.AgentBuilder.Transformer` 的方法上. 然后通过 `net.bytebuddy.dynamic.DynamicType.Builder` 构造新的类的字节码, 返回给 `Instrumentation`.
