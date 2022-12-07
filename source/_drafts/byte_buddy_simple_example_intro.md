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
**ldc** 指令会将常量池中的常量入栈, 这里是将常量池第八个常量(也就是`"A"`) 入栈. **areturn** 将栈中数据返回.


生成的新类, 也是类似的逻辑:
![EchoB](/images/ByteBuddy2.jpg)


## 源码视角: 怎么实现的
从上面字节码视角, 我们知道我们需要做两件事情:
1. 在常量池中加入 `"B"`
2. 构造 `echo` 方法的字节码,读取字节码


# 附录
