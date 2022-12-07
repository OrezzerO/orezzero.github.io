---
title: 一个简单的 Byte Buddy 例子及原理简述
date: 2022-12-06 17:08:06
categories:
- CS
- Java
tags:
- ByteBuddy
- java
---


# 例子
## 目标
我们有一个类 EchoA, 它有一个方法 `echo` 返回值是一个字符串 `"A"`:
```java
public class EchoA {
    public String echo() {
        return "A";
    }
}
```

我们想要通过 ByteBuddy 来动态生成一个类, 它的 echo 方法返回字符串 `"B"`.


## ByteBuddy 实现
我们可以这么写:

```java
public static void main(String[] args) throws Exception {
    // 使用 ByteBuddy 开始构造一个类
    DynamicType.Unloaded<EchoA> newClass = new ByteBuddy()
            .subclass(EchoA.class) // 新的类继承于 EchoA
            .method(ElementMatchers.named("echo")) // 对方法 echo 做增强
            .intercept(FixedValue.value("B")) // 增强内容是返回一个固定值 "B"
            .make(); // 构造这个 class

    Class<?> dynamicType = newClass
            .load(EchoA.class.getClassLoader()) // 使用 EchoA 的类加载器加载这个类
            .getLoaded(); // 获取被加载的类
    EchoA echoA = (EchoA) dynamicType.getDeclaredConstructor().newInstance(); // 使用反射调用构造函数, 构造新的类的实例
    System.out.println(echoA.getClass().getName()); // 打印新类类名
    System.out.println(echoA.echo()); // 调用 echo 方法并打印结果
}
```

上面这个 main 方法动态生成了一个类, 并调用这个类的 `echo` 方法,返回了字符串 `"B"`.


# 原理
## 字节码视角: 改变了什么
ByteBuddy 可以生成字节码,但是不会生成 Java 源码,我们就从字节码层面看看, ByteBuddy 做了什么.

先看下原始的 EchoA 字节码(部分):
![EchoA](/images/ByteBuddy1.jpg)

echo 方法的字节码如下:
```
0 ldc #8 <B>
2 areturn
```
**ldc** 指令会将常量池中的常量入栈, 这里是将常量池第八个常量(也就是`"A"`) 入栈. **areturn** 指令将栈中数据作为返回值返回.


生成的新类, 也是类似的逻辑:
![EchoB](/images/ByteBuddy2.jpg)


## 源码视角: 怎么实现的
ByteBuddy 是一个对 ASM 字节码框架的封装. ByteBuddy 对字节码操作做了多个层次的封装, 用户可以很方便的使用它, 但要理解它的运行原理, 有比较陡峭的学习曲线. 下面我们管中窥豹:

```java
DynamicType.Unloaded<EchoA> newClass = new ByteBuddy()
        .subclass(EchoA.class) // 新的类继承于 EchoA
        .method(ElementMatchers.named("echo")) // 对方法名为 echo 做增强
        .intercept(FixedValue.value("B")) // 增强内容是返回一个固定值 "B"
        .make(); // 构造这个 class
```

我们着重分析这段代码:`subclass`,`method`,`intercept` 这三个方法都是对 ByteBuddy 对象进行设置,没有进行具体字节码操作.

> 由于 BtyeBuddy 框架中用了很多不可变类, 这三个方法的返回值都是一个新的 ByteBuddy 实例.

最后的 `make` 方法将会进行字节码增强,产生新的类的字节码.我们具体看下 `make` 方法内部.


net.bytebuddy.dynamic.DynamicType.Builder.AbstractBase.UsingTypeWriter#make(net.bytebuddy.dynamic.TypeResolutionStrategy):
```java
public DynamicType.Unloaded<U> make(TypeResolutionStrategy typeResolutionStrategy, TypePool typePool) {
  return toTypeWriter(typePool).make(typeResolutionStrategy.resolve());
}
```

`make` 方法内部使用会构造一个 TypeWriter 去做具体的 `make` 操作.
构造 TypeWriter 的过程参考下面代码的注释
```java
protected TypeWriter<T> toTypeWriter(TypePool typePool) {
    MethodRegistry.Compiled methodRegistry = constructorStrategy   // constructorStrategy 规定了如何构造新类的构造函数, ByteBuddy 遵循约定优于配置的原则, constructorStrategy 有一个默认值,这里我们不展开讨论.
            .inject(instrumentedType, this.methodRegistry) // inject 将构造函数如何构造的 handler 插入 methodRegistry,并返回这个 methodRegistry
            .prepare(applyConstructorStrategy(instrumentedType), // prepare 方法会会根据配置 (也就是上文 method 和 intercept 方法), 将改造 echo 方法的 handler 加入 methodRegistry.
            // 具体操作是: 在需要被怎强的类 EchoA 中, 通过 过滤器(ElementMatchers.named("echo")) 找到需要被增强的方法 echo , 然后将这个方法和这个方法如何被增强 (返回固定值 value FixedValue.value("B")) 插入到 methodRegistry
                    methodGraphCompiler,
                    typeValidation,
                    visibilityBridgeStrategy,
                    new InstrumentableMatcher(ignoredMethods))
            .compile(SubclassImplementationTarget.Factory.SUPER_CLASS, classFileVersion); // compile 方法会将对应的 handler 对应的 ByteCodeAppender 和 MethodAttributeAppender 和方法对应起来,并缓存起来.

            // 最后将准备好的对象组织成 TypeWriter 返回
    return TypeWriter.Default.<T>forCreation(methodRegistry,
            auxiliaryTypes,
            fieldRegistry.compile(methodRegistry.getInstrumentedType()),
            recordComponentRegistry.compile(methodRegistry.getInstrumentedType()),
            typeAttributeAppender,
            asmVisitorWrapper,
            classFileVersion,
            annotationValueFilterFactory,
            annotationRetention,
            auxiliaryTypeNamingStrategy,
            implementationContextFactory,
            typeValidation,
            classWriterStrategy,
            typePool);
}
```

构造完成 TypeWriter 之后, 通过 make 方法最终构造出新的类的字节码, make 方法调用`net.bytebuddy.dynamic.scaffold.TypeWriter.Default.ForCreation#create` create 方法, create 方法调用 ASM 框架的方法, 将上述准备好的 ByteCodeAppender 应用到被增强的类上.


# 附录
[ByteBuddy 官方教程](https://bytebuddy.net/#/tutorial): 如果想要快速上手 ByteBuddy, 看这个官方教程最直接.
[The Java® Virtual Machine Specification Java SE 11 Edition](https://docs.oracle.com/javase/specs/jvms/se11/html/index.html) 想了解字节码可以看这个文档
