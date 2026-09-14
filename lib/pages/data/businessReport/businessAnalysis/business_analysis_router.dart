import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/business_analysis_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/cgfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/hyfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/kdfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/lsfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/mdfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/pffx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/spfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/xsth_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/yjfx_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class BusinessAnalysisRouter implements IRouterProvider {
  static const String root = '/businessAnalysis';
  static const String lsfx = '/businessAnalysis/lsfx';
  static const String kdfx = '/businessAnalysis/kdfx';
  static const String pffx = '/businessAnalysis/pffx';
  static const String hyfx = '/businessAnalysis/hyfx';
  static const String xsth = '/businessAnalysis/xsth';
  static const String cgfx = '/businessAnalysis/cgfx';
  static const String mdfx = '/businessAnalysis/mdfx';
  static const String yjfx = '/businessAnalysis/yjfx';
  static const String spfx = '/businessAnalysis/spfx';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const BusinessAnalysisPage()));
    router.define(lsfx, handler: Handler(handlerFunc: (_, __) => const LsfxPage()));
    router.define(kdfx, handler: Handler(handlerFunc: (_, __) => const KdfxPage()));
    router.define(pffx, handler: Handler(handlerFunc: (_, __) => const PffxPage()));
    router.define(hyfx, handler: Handler(handlerFunc: (_, __) => const HyfxPage()));
    router.define(xsth, handler: Handler(handlerFunc: (_, __) => const XsthPage()));
    router.define(cgfx, handler: Handler(handlerFunc: (_, __) => const CgfxPage()));
    router.define(mdfx, handler: Handler(handlerFunc: (_, __) => const MdfxPage()));
    router.define(yjfx, handler: Handler(handlerFunc: (_, __) => const YjfxPage()));
    router.define(spfx, handler: Handler(handlerFunc: (_, __) => const SpfxPage()));
  }
}
