---
title: Alibaba transmittable-thread-local 分析
date: 2022-12-15 15:11:25
categories:
- CS
- Java
tags:
- java
---


# Alibaba transmittable-thread-local 是什么
`TransmittableThreadLocal(TTL)`：在使用线程池等会池化复用线程的执行组件情况下，提供ThreadLocal值的传递功能，解决异步执行时上下文传递的问题。


# 相关文章
网上有很多 TTL 的原理分析/实践. TTL 作者在 [这里](https://github.com/alibaba/transmittable-thread-local/issues/123) 做了一个汇总. 我这篇文章就不深入细节展开了, 只写一点我自己对 TTL 笼统的理解.


# 分析
## InheritableThreadLocal 原理
在创建 `Thread` 对象时 ,会复制复父线程的 `InheritableThreadLocal` 到新的 `Thread` 对象, 通过这种方式父线程的 `ThreadLocal` 传递给子线程. 这种方式有如下问题:
* 线程池场景下,无法做到 ThreadLocal 的传递
* 传递的参数是通用引用传递, 无法做到值传递.

## TransmittableThreadLocal 原理
`TransmittableThreadLocal` 是在创建 `Runnable` 的时候做的 `ThreadLocal` 传递:
1. 在创建 `Runnable` 的时候, 将 `TransmittableThreadLocal` 存储到一个对象属性中,此时所有逻辑在父线程中执行.
2. 在执行 `Runnable.run` 时, 将上文对象中的 `TransmittableThreadLocal` 取出, 再放到 `ThreadLocal` 应该在的地方, 这个步骤的逻辑在子线程中执行.

另外`TransmittableThreadLocal` 还留有 `TtlCopier` 接口, 可以自定义实现值传递.

简单讲讲 TTL 就这么一回事,当然其中还有很多细节需要注意, 有需要的同学可以查看官方文档及官方文档汇总做进一步了解.


# 参考文档
[transmittable-thread-local repo](https://github.com/alibaba/transmittable-thread-local)
