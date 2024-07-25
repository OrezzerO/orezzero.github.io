---
title: 使用 JavaAgent 打印所有 Native 调用
date: 2022-11-23 05:13:39
categories:
- CS
- Java
tags:
- java
---


我打算对 Java 网络的底层进行拆解，将 Java 网络操作与系统调用关联起来，探究那些在公众号上频繁出现的知识点的实际运作方式。通过 strace 虽能追踪到系统调用，然而却难以清晰辨别具体是由哪行 Java 代码发起的系统调用，这中间缺失了一层 Native 层。因此，我期望把调用过程中的 Native 方法全部打印出来。


## 原理解析
众所周知，Java Agent 能够用于实现字节码增强。但 Java Native 方法不存在字节码，所以无法直接进行字节码增强。
我们需要采取迂回的策略：
1. 对 Native 方法进行重命名，并添加一个前缀。
2. 构建一个与之前 Native 方法名称相同的普通方法。
3. 借助字节码增强这个普通方法，再由该普通方法去调用 Native 方法。
例如，假设原本的 Native 方法名为 intern ，我们可以将其重命名为 enhance_intern ，然后创建一个名为 intern 的普通方法，在字节码增强这个新创建的普通方法后，由它来调用 enhance_intern 。这种方式就巧妙地解决了 Native 方法无法直接字节码增强的问题。

举个具体🌰:
修改前方法:
``` java
public native String intern();
```

修改后:
``` java
public native String enhance_intern();

public String intern(){
  enhance_intern();
}
```

## 实践细节
Native 方法名一旦更改，其与具体 Native 实现的映射关系便会遭到破坏，此时就需要借助 java.lang.instrument.Instrumentation#setNativeMethodPrefix 来重新构建映射关系。这个方法的作用在于，当 Native 方法无法被找到时，通过去除前缀再次尝试寻找。

然而，JVM 默认并不支持设置 Native 方法前缀，需要在 JavaAgent 的 manifest 中，设定 Can-Set-Native-Method-Prefix: true 。

## 看看代码
实现这么一个 Java Agent 只需要两个类, 那就直接上代码和注释了:
``` java
public class Premain {
    // premain 方法，在 Java 代理的预初始化阶段被调用
    public static void premain(String args, Instrumentation inst) {
        // 调用 recoverMain 方法进行相关操作
        recoverMain(inst);
    }

    // agentmain 方法，在 Java 代理的启动阶段被调用
    public static void agentmain(String args, Instrumentation inst) {
        // 调用 recoverMain 方法进行相关操作
        recoverMain(inst);
    }

    // recoverMain 方法，用于执行恢复主流程的操作
    public static void recoverMain(Instrumentation inst) {
        // 输出 inst 是否支持本地方法前缀
        System.out.println(inst.isNativeMethodPrefixSupported());
        // 创建 NativeWrappingClassFileTransformer 类的对象
        NativeWrappingClassFileTransformer transformer = new NativeWrappingClassFileTransformer();
        // 向 inst 添加转换器，并设置为可以重转换
        inst.addTransformer(transformer,true);
        // 为 inst 设置本地方法前缀
        inst.setNativeMethodPrefix(transformer, NativeWrappingClassFileTransformer.PREFIX);
    }
}
```

``` java
class NativeWrappingClassFileTransformer implements ClassFileTransformer {

    // 定义一个表示 BlockHound 运行时类型的 Type 对象
    static final Type BLOCK_HOUND_RUNTIME_TYPE = Type.getType("Lreactor/blockhound/BlockHoundRuntime;");
    // 定义本地方法的前缀字符串
    static final String PREFIX = "$$BlockHound$$_";

    // 构造函数
    NativeWrappingClassFileTransformer() {
    }

    /**
     * 实现 ClassFileTransformer 接口的 transform 方法
     *
     * @param loader          类加载器
     * @param className       类名
     * @param classBeingRedefined 正在被重定义的类
     * @param protectionDomain 保护域
     * @param classfileBuffer 类文件缓冲区
     * @return 转换后的字节数组，如果不进行转换则返回 null
     */
    @Override
    public byte[] transform(
            ClassLoader loader,
            String className,
            Class<?> classBeingRedefined,
            ProtectionDomain protectionDomain,
            byte[] classfileBuffer
    ) {
//        if (!className.startsWith("java/net/")) {
//            return null;
//        }

        // 创建 ClassReader 对象来读取类文件缓冲区
        ClassReader cr = new ClassReader(classfileBuffer);
        // 创建 ClassWriter 对象用于写入转换后的类
        ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_MAXS);

        try {
            // 接受 NativeWrappingClassVisitor 进行类的访问和转换
            cr.accept(new NativeWrappingClassVisitor(cw, className), 0);

            // 获取转换后的字节数组
            classfileBuffer = cw.toByteArray();
        } catch (Throwable e) {
            // 打印异常堆栈跟踪
            e.printStackTrace();
            // 抛出异常
            throw e;
        }

        // 返回转换后的类文件字节数组
        return classfileBuffer;
    }

    // 内部静态类 NativeWrappingClassVisitor，继承自 ClassVisitor
    static class NativeWrappingClassVisitor extends ClassVisitor {

        // 存储类名
        private final String className;

        // 构造函数
        NativeWrappingClassVisitor(ClassVisitor cw, String internalClassName) {
            // 调用父类构造函数
            super(ASM7, cw);
            // 初始化类名
            this.className = internalClassName;
        }

        /**
         * 重写 visitMethod 方法，处理方法访问
         *
         * @param access          方法的访问标志
         * @param name            方法名
         * @param descriptor      方法描述符
         * @param signature       方法签名
         * @param exceptions      方法抛出的异常
         * @return 方法访问器
         */
        @Override
        public MethodVisitor visitMethod(int access,
                                         String name,
                                         String descriptor,
                                         String signature,
                                         String[] exceptions) {
            // 如果方法不是本地方法
            if ((access & ACC_NATIVE) == 0) {
                // 调用父类的 visitMethod 方法
                return super.visitMethod(access, name, descriptor, signature, exceptions);
            }

            // 访问修改后的本地方法
            super.visitMethod(
                    ACC_NATIVE | ACC_PRIVATE | ACC_FINAL | (access & ACC_STATIC),
                    PREFIX + name,
                    descriptor,
                    signature,
                    exceptions
            );

            // 访问原始的非本地方法
            MethodVisitor delegatingMethodVisitor = super.visitMethod(
                    access & ~ACC_NATIVE, name, descriptor, signature, exceptions);
            delegatingMethodVisitor.visitCode();

            // 返回自定义的方法访问器
            return new MethodVisitor(ASM7, delegatingMethodVisitor) {

                @Override
                public void visitEnd() {

                    // 添加打印语句打印方法名
                    visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
                    visitLdcInsn("Method called: " + className + "." + name);
                    visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);


                    Type returnType = Type.getReturnType(descriptor);
                    Type[] argumentTypes = Type.getArgumentTypes(descriptor);
                    boolean isStatic = (access & ACC_STATIC)!= 0;
                    if (!isStatic) {
                        visitVarInsn(ALOAD, 0);
                    }
                    int index = isStatic? 0 : 1;
                    for (Type argumentType : argumentTypes) {
                        visitVarInsn(argumentType.getOpcode(ILOAD), index);
                        index += argumentType.getSize();
                    }

                    visitMethodInsn(
                            isStatic? INVOKESTATIC : INVOKESPECIAL,
                            className,
                            PREFIX + name,
                            descriptor,
                            false
                    );

                    visitInsn(returnType.getOpcode(IRETURN));
                    visitMaxs(0, 0);
                    super.visitEnd();
                }
            };
        }

    }
}
```
