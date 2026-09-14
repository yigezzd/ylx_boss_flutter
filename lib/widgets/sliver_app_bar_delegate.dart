import 'package:flutter/material.dart';

/// 固定高度的吸顶头部代理，配合 [SliverPersistentHeader] 使用。
class SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  SliverAppBarDelegate(this._widget, this._minHeight);

  final Widget _widget;
  final double _minHeight;

  @override
  double get minExtent => _minHeight;

  @override
  double get maxExtent => _minHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _widget;
  }

  @override
  bool shouldRebuild(SliverAppBarDelegate oldDelegate) {
    return true;
  }
}
