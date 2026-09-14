---
trigger: always_on
---

# 列表渲染性能优化规则（PDA/低端设备）

## 适用范围

当生成的代码涉及列表渲染（`ListView`、`GridView`、`CustomScrollView` 等滚动列表）时，**必须**考虑商米 L2 等 PDA 低端设备的滑动性能，严格执行以下优化措施。

## 强制规则

### 1. 提取独立 Widget

将列表项构建逻辑提取为独立的 `StatelessWidget` 类，利用 Flutter 的 widget 复用机制，禁止在 `build` 方法中直接内联构建卡片。

### 2. 设置 cacheExtent

列表组件必须设置 `cacheExtent: 800`，提前渲染屏幕外的卡片，减少快速滑动时的掉帧。

```dart
ListView.builder(
  cacheExtent: 800,
  // ...
)
```

### 3. 禁止使用 BoxShadow

`BoxShadow` 涉及高斯模糊，在低端设备上开销极大。改用 `Border.all` 或 `Container` 边框实现视觉效果。

```dart
// ❌ 禁止
BoxDecoration(
  boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black12)],
)

// ✅ 推荐
BoxDecoration(
  border: Border.all(color: Colors.grey.shade300),
  borderRadius: BorderRadius.circular(8),
)
```

### 4. RepaintBoundary 隔离重绘

每个列表项外层必须包裹 `RepaintBoundary`，隔离重绘范围，避免整屏刷新。

```dart
RepaintBoundary(
  child: _ItemCard(item: item),
)
```

### 5. 图片优化

- 使用 `Image.network` 的 `cacheWidth` / `cacheHeight` 控制解码尺寸，避免全分辨率解码。
- 移除 `ClipRRect` 裁剪，改用 `Container` 圆角背景。

```dart
Image.network(
  url,
  cacheWidth: 200,
  cacheHeight: 200,
  fit: BoxFit.cover,
)
```

### 6. 减少 Material 组件开销

优先使用 `GestureDetector` + `Container` 替代 `OutlinedButton` / `ElevatedButton` 等重量级 Material 组件。

```dart
// ❌ 避免在列表项中使用
OutlinedButton(onPressed: () {}, child: Text('操作'))

// ✅ 推荐
GestureDetector(
  onTap: () {},
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).primaryColor),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('操作'),
  ),
)
```

### 7. 避免列表项内复杂动画

低端设备上禁止在列表项中使用 `AnimationController` 或隐式动画（如 `AnimatedContainer`、`AnimatedOpacity`）。

### 8. static 声明占位符

`_placeholder()` 等辅助方法必须声明为 `static`，避免每次 `build` 时重复创建闭包。
