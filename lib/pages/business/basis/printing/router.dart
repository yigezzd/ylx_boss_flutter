import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/printing/edit_product_group.dart';
import 'package:flutter_deer/pages/business/basis/printing/label_print_home.dart';
import 'package:flutter_deer/pages/business/basis/printing/receipt_detail.dart';
import 'package:flutter_deer/pages/business/basis/printing/receipts_list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class PrintingRouter implements IRouterProvider {
  static const String labelPrintHome = '/basis/printing/labelPrintHome';
  static const String receiptsList = '/basis/printing/receiptsList';
  static const String receiptDetail = '/basis/printing/receiptDetail';
  static const String editProductGroup = '/basis/printing/editProductGroup';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      labelPrintHome,
      handler: Handler(
        handlerFunc: (_, __) => const LabelPrintHomePage(),
      ),
    );
    router.define(
      receiptsList,
      handler: Handler(
        handlerFunc: (_, __) => const ReceiptsListPage(),
      ),
    );
    router.define(
      receiptDetail,
      handler: Handler(
        handlerFunc: (_, __) => const ReceiptDetailPage(),
      ),
    );
    router.define(
      editProductGroup,
      handler: Handler(
        handlerFunc: (_, __) => const EditProductGroupPage(),
      ),
    );
  }
}
