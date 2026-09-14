import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Boss 项目 SVG 图标组件（本地 asset 加载）
///
/// SVG 文件已内置于 assets/svg/ 目录，无需网络请求，
/// 彻底规避 CORS / DOCTYPE 等问题。
class BossSvgIcon extends StatelessWidget {
  /// SVG 文件名，如 'probook.svg'
  final String svgFile;

  /// 图标尺寸（宽 = 高）
  final double size;

  /// 可选颜色覆盖（传 null 则保留 SVG 原色）
  final Color? color;

  const BossSvgIcon({
    super.key,
    required this.svgFile,
    this.size = 44,
    this.color,
  });

  /// SVG 资源路径前缀
  static const String _assetPrefix = 'assets/svg/';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      '$_assetPrefix$svgFile',
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
      placeholderBuilder: (_) => _placeholder(),
    );
  }

  /// 加载失败 / 文件不存在时的占位
  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(
        Icons.image_outlined,
        color: const Color(0xFFBDBDBD),
        size: size * 0.5,
      ),
    );
  }
}
