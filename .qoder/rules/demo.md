---
trigger: always_on
---

# Flutter 重构参考规则

## 业务逻辑参考

- 所有页面和代码的业务逻辑、功能实现，统一参考 `E:\VUE\ylx-boss` 项目
- 当前 Flutter 项目是基于 boss 项目重构的，业务逻辑保持一致
- 确保页面内容、数据流转、接口调用、交互逻辑与 boss 项目保持一致

## UI 规范

- UI 效果以当前 Flutter 项目的 UI 框架为准
- 页面样式需美观、好看，符合 Flutter Material Design 规范
- 不照搬 Vue 项目的样式，但需还原业务展示内容

## 开发流程

1. 先阅读 `E:\VUE\ylx-boss` 对应页面的业务逻辑
2. 理解数据结构、接口调用、状态管理方式
3. 在 Flutter 中用对应的实现方式（如 Provider/Bloc/GetX）还原逻辑
4. UI 层使用 Flutter 组件重新设计，保持美观

## 注意事项

- Vue 项目中的 API 接口路径和参数可直接复用
- 页面跳转逻辑、权限判断、数据校验等业务规则需与 boss 项目一致
- 错误处理、loading 状态、空数据状态等交互细节参考 boss 项目实现
