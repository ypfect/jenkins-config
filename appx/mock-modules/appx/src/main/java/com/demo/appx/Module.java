package com.demo.appx;

/** 业务模块接口，各模块实现并通过 META-INF/appx-modules 清单注册。 */
public interface Module {
  String name();
}
