class HttpApi {
  static const String users = 'users/simplezhli';
  static const String search = 'search/repositories';
  static const String subscriptions = 'users/simplezhli/subscriptions';
  static const String upload = 'uuc/upload-inco';

  /// 灵犀管店登录相关接口
  // static const String baseUrlYlx = 'http://192.168.8.43:9099/LxSvr/web/'; // 李宇智
  // static const String baseUrlYlx = 'http://192.168.8.62:9099/LxSvr/web/'; // 朱远杰
  // static const String baseUrlYlx = 'http://192.168.8.41:9099/LxSvr/web/'; // 杨潇
  // static const String baseUrlYlx = 'http://dev.bypos.net/LxSvr/web/';
  static const String baseUrlYlx = 'https://yun.bypos.net/LxSvr/web/';

  /// 获取门店列表（登录第一步）
  static const String getLoginList = 'getLoginList';

  /// 登录（登录第二步）
  static const String lxlogin = 'lxlogin';

  /// 采购入库相关 API（灵犀系统）
  static const String purchaseInstoreList = 'cgstockin/findList';
  static const String purchaseInstoreGetInfo = 'cgstockin/getInfo';
  static const String purchaseInstoreSave = 'cgstockin/save';
  static const String purchaseInstoreSign = 'cgstockin/sign';
  static const String purchaseInstoreRetsign = 'cgstockin/retsign';
  static const String purchaseInstoreDelBill = 'cgstockin/delBill';
  static const String purchaseInstorePrint = 'airprint/setWxPrintRw'; // 打印单据
  static const String purchaseUpdateCgPrice = 'cgstockin/updateCgPrice'; // 切换供应商/机构时批量更新采购价格

  /// 基础数据查询 API
  static const String supplierList = 'supplierinfo/findList'; // 供应商列表
  static const String storeGetList = 'store/getList'; // 机构列表
  static const String storeGetInfo = 'store/getInfo'; // 机构详情
  static const String counterGetList = 'bi/counter/getList'; // 仓库列表
  static const String sysUserList = 'sysuser/findList'; // 系统用户列表
  static const String sysUserSave = 'sysuser/save'; // 保存用户（新增/编辑）
  static const String sysUserDelete = 'sysuser/delete'; // 删除用户
  static const String sysUserGetInfo = 'sysuser/getInfo'; // 获取用户详情
  static const String sysUserGenerateCode = 'sysuser/generateCode'; // 自动生成工号
  static const String sysUserAdd = 'sysuser/add'; // 新增用户(旧)
  static const String sysUserUpdate = 'sysuser/update'; // 更新用户(旧)
  static const String sysUserGetRoleConfig = 'sysuser/getUserRoleConfig'; // 角色配置
  static const String roleFindList = 'role/findList'; // 角色列表
  static const String productGetList = 'bi/product/getProductList'; // 商品列表
  static const String machineGetList = 'machine/getMachineList'; // 站点设备列表
  static const String machineCheck = 'machine/checkMachine'; // 站点校验
  static const String machineUpdate = 'machine/update'; // 站点更新
  static const String machineOperate = 'machine/operate'; // 站点操作（删除）
  static const String sysSeatFindList = 'sysseat/findList'; // 用户授权席位列表
  static const String sysSeatBindSeat = 'sysseat/bindSeat'; // 绑定席位
  static const String sysSeatUnbindSeat = 'sysseat/unbindSeat'; // 解绑席位
  static const String sysSeatUpdateStop = 'sysseat/updateStop'; // 启用/停用
  static const String stockproductGetBacthList = 'stockproduct/getBacthList'; // 商品批次列表
  static const String itemClassGetList = 'bi/itemclass/getList'; // 商品分类列表
  static const String brandList = 'bi/brand/getBrandList'; // 品牌列表
  static const String locationGetList = 'bi/location/getList'; // 货架编号列表
  static const String typeGetListandCode = 'bi/type/getTypeListandCode'; // 分类树（含编码）
  static const String typeAddTypeInfo = 'bi/type/addTypeInfo'; // 新增分类
  static const String typeUpdateTypeInfo = 'bi/type/updateTypeInfo'; // 修改分类
  static const String typeDelTypeInfo = 'bi/type/delTypeInfo'; // 删除分类
  static const String typeGetCode = 'bi/type/getCode'; // 获取分类编码
  static const String getTypeOfCode = 'bi/product/getTypeOfCode'; // 获取分类编码
  static const String productGetExtendList = 'bi/product/getProductExtendList'; // 商品扩展列表（单位/规格）
  static const String otherdataGetList = 'bi/otherdata/getList'; // 通用数据查询（选送货人/业务员等）

  /// 采购订货单 API
  static const String cgorderFindList = 'cgorder/findList';
  static const String cgorderGetInfo = 'cgorder/getInfo';
  static const String cgorderSave = 'cgorder/save';
  static const String cgorderSign = 'cgorder/sign';
  static const String cgorderRetsign = 'cgorder/retsign';
  static const String cgorderDelBill = 'cgorder/delBill';
  static const String cgorderStop = 'cgorder/stop';
  static const String cgorderPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 采购退货单 API（与采购入库共用 cgstockin/ 前缀，对齐 Vue cgth/index.vue 及 edit.vue）
  static const String cgthFindList = 'cgstockin/findList';
  static const String cgthGetInfo = 'cgstockin/getInfo';
  static const String cgthSave = 'cgstockin/save';
  static const String cgthSign = 'cgstockin/sign';
  static const String cgthRetsign = 'cgstockin/retsign';
  static const String cgthDelBill = 'cgstockin/delBill';
  static const String cgthPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 采购计划单 API
  static const String cgplanFindList = 'cgplan/findList';
  static const String cgplanGetInfo = 'cgplan/getInfo';
  static const String cgplanSave = 'cgplan/save';
  static const String cgplanSign = 'cgplan/sign';
  static const String cgplanRetsign = 'cgplan/retsign';
  static const String cgplanDelBill = 'cgplan/delBill';
  static const String cgplanPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 审批流配置 API
  static const String reviewTypeConfigGetNewBillSignUser = 'reviewTypeConfig/getNewBillSignUser';
  static const String getReviewBillTypeList =
      'reviewTypeConfig/getReviewBillTypeList'; // 多级审批列表（判断是否显示已驳回tab）

  /// 自采申请单 API
  static const String cgzcFindList = 'cgzc/findList';
  static const String cgzcGetInfo = 'cgzc/getInfo';
  static const String cgzcSave = 'cgzc/save';
  static const String cgzcSign = 'cgzc/sign';
  static const String cgzcRetsign = 'cgzc/retsign';
  static const String cgzcDelBill = 'cgzc/delBill';
  static const String cgzcPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 退货申请单 API
  static const String cgthsqGenerateCgStockRet = 'cgzc/generateCgStockRet';

  /// 调拨申请单 API（对齐 Vue chain/AllotApply）
  static const String dborderFindList = 'dborder/findList';
  static const String dborderGetInfo = 'dborder/getInfo';
  static const String dborderSave = 'dborder/save';
  static const String dborderSign = 'dborder/sign';
  static const String dborderRetsign = 'dborder/retsign';
  static const String dborderDelBill = 'dborder/delBill';
  static const String dborderUpdateLsPrice = 'dborder/updateLsPrice'; // 选仓库后刷新商品货架号
  static const String dborderPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 调拨出库单 API（对齐 Vue chain/AllotDelivery）
  static const String dbstockoutFindList = 'dbstockout/findList';
  static const String dbstockoutGetInfo = 'dbstockout/getInfo';
  static const String dbstockoutSave = 'dbstockout/save';
  static const String dbstockoutSign = 'dbstockout/sign';
  static const String dbstockoutRetsign = 'dbstockout/retsign';
  static const String dbstockoutDelBill = 'dbstockout/delBill';
  static const String dbstockoutPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 调拨入库单 API（对齐 Vue chain/AllotEntry）
  static const String dbstockinFindList = 'dbstockout/findList'; // 列表复用同一接口
  static const String dbstockinGetInfo = 'dbstockout/getInfo'; // 详情复用同一接口
  static const String dbstockinSave = 'dbstockout/inSave';
  static const String dbstockinSign = 'dbstockout/inSign';
  static const String dbstockinRetsign = 'dbstockout/retInSign';
  static const String dbstockinDelBill = 'dbstockout/delBill'; // 删除复用同一接口
  static const String dbstockinPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 配送发货单 API（对齐 Vue chain/deliver）
  static const String psstockoutFindList = 'psstockout/findList';
  static const String psstockoutGetInfo = 'psstockout/getInfo';
  static const String psstockoutSave = 'psstockout/save';
  static const String psstockoutSign = 'psstockout/sign';
  static const String psstockoutRetsign = 'psstockout/retsign';
  static const String psstockoutDelBill = 'psstockout/delBill';
  static const String psstockoutPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 配送收货单 API（对齐 Vue chain/receivingnote）
  static const String psstockinFindList = 'psstockin/findList';
  static const String psstockinGetInfo = 'psstockin/getInfo';
  static const String psstockinSave = 'psstockin/save';
  static const String psstockinSign = 'psstockin/sign';
  static const String psstockinRetsign = 'psstockin/retsign';
  static const String psstockinReject = 'psstockin/reject'; // 拒收
  static const String psstockinPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 配退申请单 API（对齐 Vue chain/returnApplication）
  static const String psrefundapplyFindList = 'psrefundapply/findList';
  static const String psrefundapplyGetInfo = 'psrefundapply/getInfo';
  static const String psrefundapplySave = 'psrefundapply/save';
  static const String psrefundapplySign = 'psrefundapply/sign';
  static const String psrefundapplyRetsign = 'psrefundapply/retsign';
  static const String psrefundapplyDelBill = 'psrefundapply/delBill';
  static const String psrefundapplyPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 配退发货单 API（对齐 Vue chain/returnDeliver）
  static const String psrefundoutFindList = 'psrefundout/findList';
  static const String psrefundoutGetInfo = 'psrefundout/getInfo';
  static const String psrefundoutSave = 'psrefundout/save';
  static const String psrefundoutSign = 'psrefundout/sign';
  static const String psrefundoutRetsign = 'psrefundout/retsign';
  static const String psrefundoutDelBill = 'psrefundout/delBill';
  static const String psrefundoutPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 配退收货单 API（对齐 Vue chain/returentakeDelivery）
  static const String psrefundinFindList = 'psrefundin/findList';
  static const String psrefundinGetInfo = 'psrefundin/getInfo';
  static const String psrefundinSave = 'psrefundin/save';
  static const String psrefundinSign = 'psrefundin/sign';
  static const String psrefundinRetsign = 'psrefundin/retsign';
  static const String psrefundinReject = 'psrefundin/reject'; // 拒收
  static const String psrefundinPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// WMS 收货任务 API（对齐 Vue wms/receiveTakList）
  static const String wmsReceiveTakList = 'wms/task/receive/getWmsReceiveTakList'; // 收货任务列表
  static const String wmsReceiveGetInfo = 'wms/task/receive/getInfo'; // 收货任务详情
  static const String wmsReceiveUpdate = 'wms/task/receive/updateReceiveTak'; // 保存收货数据
  static const String wmsReceiveRetsign = 'wms/task/receive/retsign'; // 反审核
  static const String wmsFinishReceiveTak = 'cgstockin/finishReceiveTak'; // 完成收货
  static const String wmsReceivePrint = 'airprint/setWxPrintRw'; // 打印单据

  /// WMS 上架 API（对齐 Vue wms/launch）
  static const String wmsLaunchList = 'wms/stock/getWmsLaunchList'; // 上架任务列表（按单据）
  static const String wmsLaunchProList = 'wms/stock/getWmsLaunchProList'; // 上架任务列表（按商品）
  static const String wmsLaunchListByTray = 'wms/task/receive/getWmsLaunchListByTray'; // 扫托盘码查上架明细
  static const String wmsLaunchSave = 'wms/task/receive/WmsLaunch'; // 上架保存
  static const String wmsLaunchListSave = 'wms/task/receive/WmsLaunchList'; // 上架批量保存（按单据分组）
  static const String wmsLocationList = 'bi/location/getWmsLocationList'; // 货位号列表（上架）
  static const String wmsRemoveLocationList = 'bi/location/getWmsRemoveLocationList'; // 可移入货位列表
  static const String dbStockOutGetInfo = 'dbstockout/getInfo'; // 调拨入库详情

  /// WMS 补货 API（对齐 Vue wms/restock）
  static const String wmsReStockList = 'wms/stock/getWmsReStockList'; // 补货列表
  static const String wmsProductLocationStockList =
      'wms/stock/report/getProductLocationStockList'; // 商品货位库存
  static const String wmsRestockSave = 'wms/task/receive/restock'; // 补货保存

  /// WMS 货位库存查询 API（对齐 Vue wms/stockQuery）
  static const String wmsStockByProduct = 'wms/stock/getWmsStockByProduct'; // 商品维度库存
  static const String wmsStockSumByShelf = 'wms/stock/getWmsStockSumByShelf'; // 货位维度库存
  static const String wmsMoveStock = 'wms/task/receive/moveStock'; // 移货保存

  /// WMS 设置 API（对齐 Vue wms/wmsSet）
  static const String wmsSetSave = 'airWmsSet/saveWxWmsSet'; // 保存WMS设置
  static const String wmsSetGet = 'airWmsSet/getWxWmsSet'; // 获取WMS设置

  /// 直配订单 API
  static const String cgotherFindList = 'cgother/findList';
  static const String cgotherGetInfo = 'cgother/getInfo';
  static const String cgotherSave = 'cgother/save';
  static const String cgotherSign = 'cgother/sign';
  static const String cgotherRetsign = 'cgother/retsign';
  static const String cgotherDelBill = 'cgother/delBill';
  static const String cgotherStop = 'cgother/stop';
  static const String cgotherPrint = 'airprint/setWxPrintRw'; // 打印单据

  /// 越库订单 API
  static const String cgothercdGetInfo = 'cgothercd/getInfo';

  /// 要货申请单 API
  static const String yhorderFindList = 'yhorder/findList';
  static const String yhorderGetInfo = 'yhorder/getInfo';
  static const String yhorderSave = 'yhorder/save';
  static const String yhorderSign = 'yhorder/sign';
  static const String yhorderRetsign = 'yhorder/retsign';
  static const String yhorderDelBill = 'yhorder/delBill';
  static const String yhorderStop = 'yhorder/stop';
  static const String yhorderPrint = 'airprint/setWxPrintRw';

  /// 要货模板 API
  static const String yhtemplateFindList = 'yhtemplate/findList';
  static const String yhtemplateFindProList = 'yhtemplate/findProList';

  /// 首页数据看板相关 API
  static const String homeGetHomeCard = 'home/getHomeCard'; // 首页卡片顺序配置
  static const String homeGetBusinessOverview = 'home/getBusinessOverview'; // 经营概览（零售）
  static const String homeGetPFBusinessOverview = 'home/getPFBusinessOverview'; // 经营概览（批发）
  static const String homeGetBusinessStatistics = 'home/getBusinessStatistics'; // 营业趋势统计（零售）
  static const String homeGetPFBusinessStatistics = 'home/getPFBusinessStatistics'; // 营业趋势统计（批发）
  static const String homeGetPaySum = 'home/getPaySum'; // 付款方式汇总（零售）
  static const String homeGetPFPaySum = 'home/getPFPaySum'; // 付款方式汇总（批发）
  static const String homeGetSaleType = 'home/getSaleType'; // 分类销售榜（零售）
  static const String homeGetPFSaleType = 'home/getPFSaleType'; // 分类销售榜（批发）
  static const String homeGetSaleProd = 'home/getSaleProd'; // 单品销售榜（零售）
  static const String homeGetPFSaleProd = 'home/getPFSaleProd'; // 单品销售榜（批发）
  static const String homeSaveHomeCard = 'home/saveHomeCard'; // 保存卡片配置
  static const String getIndexTipTotal = 'stockwarn/getIndexTipTotal'; // 首页库存不足提醒
  static const String getReviewBillStatusFlowResp =
      'reviewTypeConfig/getReviewBillStatusFlowResp'; // 单据审批提醒

  /// 收银流水 API
  static const String saleSelectFindSaleBill = 'saleselect/findSaleBill'; // 收银流水列表
  static const String saleSelectBillOperate =
      'saleselect/billOperate'; // 外卖拣货-领取任务等操作（operate=1 领取）
  static const String saleFindSaleFlowDeail = 'sale/findSaleFlowDeail'; // 收银流水详情
  static const String paywayGetList = 'bi/payway/getList'; // 支付方式列表

  /// 收银统计 API
  static const String cashreconGetCasherForDaySummerybyname =
      'cashrecon/getCasherForDaySummerybyname'; // 收银员统计
  static const String cashreconFindAccountPayTotal = 'cashrecon/findAccountPayTotal'; // 币种统计
  static const String cashreconFindSaleJkd = 'cashrecon/findSaleJkd'; // 交班统计
  static const String cashreconGetSaleJkdInfo = 'cashrecon/getSaleJkdInfo'; // 交班详情

  /// 收银监控 API
  static const String summaryStoreStoreSale = 'summary_store/storeSale'; // 门店分析列表
  static const String areaGetSysAreaList = 'area/getSysAreaList'; // 区域列表

  /// 异常监控 API
  static const String saleCashMonitorGetCashMonitor = 'sale/cashMonitor/getCashMonitor'; // 异常监控列表
  static const String saleCashMonitorGetCashMonitorDetail =
      'sale/cashMonitor/getCashMonitorDetail'; // 异常监控明细

  /// 动销率分析 API
  static const String sellthroughStoreSellThrough = 'sellthrough/storeSellThrough'; // 门店动销率
  static const String sellthroughTypeSellThrough = 'sellthrough/typeSellThrough'; // 商品类别动销率
  static const String sellthroughProductSellThrough =
      'sellthrough/productSellThrough'; // 动销/未动销品项明细

  /// 经营分析 API
  static const String bossJyfxGetData = 'boss_jyfx/getData'; // 经营分析数据汇总
  static const String bossJyfxGetLsfx = 'boss_jyfx/getLsfx'; // 零售分析
  static const String bossJyfxGetKdfx = 'boss_jyfx/getKdfx'; // 客单分析
  static const String bossJyfxGetPffx = 'boss_jyfx/getPffx'; // 批发分析
  static const String bossJyfxGetHyfx = 'boss_jyfx/getHyfx'; // 会员分析列表
  static const String bossJyfxGetHyfxHead = 'boss_jyfx/getHyfxHead'; // 会员分析头部（VIP等级）
  static const String bossJyfxGetXsth = 'boss_jyfx/getXsth'; // 销售退货
  static const String bossJyfxGetCgfx = 'boss_jyfx/getCgfx'; // 采购分析
  static const String bossJyfxGetMdfx = 'boss_jyfx/getMdfx'; // 门店分析
  static const String bossJyfxGetYjfx = 'boss_jyfx/getYjfx'; // 业绩分析
  static const String bossJyfxGetSpfx = 'boss_jyfx/getSpfx'; // 商品分析
  static const String bossJyfxGetFlfx = 'boss_jyfx/getFlfx'; // 类别分析
  static const String bossJyfxGetPpfx = 'boss_jyfx/getPpfx'; // 品牌分析
  static const String bossJyfxGetHsfx = 'boss_jyfx/getHsfx'; // 供应商分析
  static const String bossJyfxGetSpfxInfo = 'boss_jyfx/getSpfxInfo'; // 商品详情

  /// 商品库存汇总
  static const String stockproductGetProductStockTotal = 'stockproduct/getProductStockTotal';

  /// 商品ABC分析 API
  static const String productabcGetAmtABC = 'productabc/getAmtABC'; // 商品-销售金额ABC
  static const String productabcGetQtyABC = 'productabc/getQtyABC'; // 商品-销售数量ABC
  static const String productabcGetGrossABC = 'productabc/getGrossABC'; // 商品-毛利ABC

  /// 类别ABC分析 API
  static const String productabcGetTypeAmtABC = 'productabc/getTypeAmtABC'; // 类别-销售金额ABC
  static const String productabcGetTypeQtyABC = 'productabc/getTypeQtyABC'; // 类别-销售数量ABC
  static const String productabcGetTypeGrossABC = 'productabc/getTypeGrossABC'; // 类别-毛利ABC

  /// 库存分析 API
  static const String productErrGetList = 'product_err/getProductErrList'; // 畅缺/滞销/零库存/负库存/进货未销
  static const String stockwarnGetStockLow = 'stockwarn/getStockLow'; // 库存预警-库存不足
  static const String stockwarnGetStockOver = 'stockwarn/getStockOver'; // 库存预警-库存过量
  static const String stockwarnGetValidDateWarn = 'stockwarn/getValidDateWarn'; // 有效期预警

  /// 会员分析 API
  static const String addVipAnalysisList = 'assistant/getAddVipAnalysisList'; // 新增会员分析
  static const String vipSaleRankingList = 'vipTable/VipSaleRankingList'; // 消费排行
  static const String vipFavourableAnalysisList = 'vipTable/VipFavourableAnalysisList'; // 优惠券分析

  /// 语音识别 NLS Token
  static const String nlsGetToken = 'nls/getToken'; // 获取阿里云NLS Token

  /// 商品管理 API
  static const String productGetInfo = 'bi/product/getProductInfo'; // 商品详情
  static const String productAddInfo = 'bi/product/addProductInfo'; // 保存/新增商品
  static const String productDelInfo = 'bi/product/delProductInfo'; // 删除商品
  static const String productGetTypeOrSuppBarcode = 'bi/product/getTypeOrSuppBarcode'; // 自动生成条码
  static const String productBarCodeGeneration = 'bi/product/barCodeGeneration'; // 条码生成
  static const String productGetTypeOfCode = 'bi/product/getTypeOfCode'; // 获取分类编码
  static const String unitGetList = 'bi/unit/getUnitList'; // 单位列表
  static const String fileUpload = 'fileUpload'; // 图片上传(base64)
  static const String productPdBarcode = 'bi/product/pdBarcodeProduct'; // 校验条码重复
  static const String productCheckDelSize = 'bi/product/checkDelProductSize'; // 校验删除包装单位

  /// 按条码查关联商品（basis/commodity/component/packconfig.vue handleBarCodeBlur）
  static const String productFindBarcodeCode = 'bi/product/findProductBarcodeCode';
  static const String productGetPlu = 'bi/product/getPlu'; // 获取PLU码

  /// APP版本检查更新
  static const String appCheckVersion = 'version/getversion'; // 查询版本

  /// 收银授权码
  static const String getAuthCode = 'sysuser/getAuthCode'; // 获取授权码

  /// 标签打印设置
  static const String getLabelPrintParams = 'wxprint/getLabelPrintParams'; // 获取标签打印配置
  static const String saveLabelPrintParams = 'wxprint/saveLabelPrintParams'; // 保存标签打印配置

  /// 业务打印设置
  static const String getWxPrintSet = 'airprint/getWxPrintSet'; // 获取业务打印配置
  static const String saveWxPrintSet = 'airprint/saveWxPrintSet'; // 保存业务打印配置
  static const String getModelList = 'airprint/getModelList'; // 获取打印模板分类
  static const String getTemplateListWx = 'airprint/getTemplateListWx'; // 获取打印模板列表
  static const String setTemplateWxDef = 'airprint/setTemplateWxDef'; // 设为默认模板

  /// 供应商管理 API
  static const String supplierGetInfo = 'supplierinfo/getSupplierInfo'; // 供应商详情
  static const String supplierSave = 'supplierinfo/save'; // 保存供应商
  static const String supplierDelete = 'supplierinfo/delete'; // 删除供应商
  static const String supplierGenerateCode = 'supplierinfo/generateCode'; // 生成供应商编码
  static const String supplierTypeGetList = 'suppliertype/getTypeListandCode'; // 供应商分类列表
  static const String supplierFindSupplierFilesList =
      'supplierinfo/findSupplierFilesList'; // 供应商证照过期提醒列表

  /// 盘点计划
  static const String stockplanFindList = 'stockplan/findList';
  static const String stockplanGetInfo = 'stockplan/getInfo';
  static const String stockplanSave = 'stockplan/save';
  static const String stockplanDelBill = 'stockplan/delBill';

  /// 预盘单
  static const String stockprecheckFindList = 'stockprecheck/findList';
  static const String stockprecheckGetInfo = 'stockprecheck/getInfo';
  static const String stockprecheckSave = 'stockprecheck/save';
  static const String stockprecheckDelBill = 'stockprecheck/delBill';
  static const String stockprecheckSign = 'stockprecheck/sign';
  static const String stockprecheckResign = 'stockprecheck/resign';

  /// 快速盘点
  static const String stockcheckfastFindList = 'stockcheckfast/findList';
  static const String stockcheckfastGetInfo = 'stockcheckfast/getInfo';
  static const String stockcheckfastSave = 'stockcheckfast/save';
  static const String stockcheckfastDelBill = 'stockcheckfast/delBill';
  static const String stockcheckfastSign = 'stockcheckfast/sign';

  /// 其他出库/入库单 API（共用 stockmodify 前缀）
  static const String stockModifyFindList = 'stockmodify/findList';
  static const String stockModifyGetInfo = 'stockmodify/getInfo';
  static const String stockModifySave = 'stockmodify/save';
  static const String stockModifySign = 'stockmodify/sign';
  static const String stockModifyDelBill = 'stockmodify/delBill';
  static const String stockModifyResign = 'stockmodify/resign';

  /// 转仓单 API
  static const String stockRollFindList = 'stockroll/findList';
  static const String stockRollGetInfo = 'stockroll/getInfo';
  static const String stockRollSave = 'stockroll/save';
  static const String stockRollSign = 'stockroll/sign';
  static const String stockRollDelBill = 'stockroll/delBill';
  static const String stockRollResign = 'stockroll/resign';

  /// 成本变更单 API
  static const String costChangeFindList = 'costchange/findList';
  static const String costChangeGetInfo = 'costchange/getInfo';
  static const String costChangeSave = 'costchange/save';
  static const String costChangeSign = 'costchange/sign';
  static const String costChangeDelBill = 'costchange/delBill';
  static const String costChangeResign = 'costchange/resign';

  /// 库存查询 API
  static const String stockproductGetProStockTotal = 'stockproduct/getProStockTotal'; // 库存查询列表
  static const String stockproductGetProStockInfo = 'stockproduct/getProStockInfo'; // 库存商品详情
  static const String stockproductGetKcProductSupPrice =
      'stockproduct/getKcProductSupPrice'; // 供应商价格
  static const String stockproductGetKcProductSid = 'stockproduct/getKcProductSid'; // 机构库存

  /// 权限相关 API
  static const String roleGetInfoRetMap = 'role/getInfoRetMap'; // 获取权限map（tabbar切换时刷新）

  /// 附件管理 API
  static const String fillupByAttachFile = 'fillupByAttachFile'; // 上传附件(base64)
  static const String delFileList = 'delFileList'; // 删除附件
  static const String updateBillFile = 'updateBillFile'; // 同步单据附件列表

  /// 关于（代理商信息）
  static const String getDls = 'store/getDls'; // 获取代理商信息

  /// 批发模块 API
  /// 客户管理
  static const String customerFindList = 'customerinfo/getList';
  static const String customerGetInfo = 'customerinfo/getCustomerInfo';
  static const String customerSave = 'customerinfo/save';
  static const String customerGenerateCode = 'customerinfo/generateCode';

  /// 批发订货
  static const String pfOrderFindList = 'pforder/findList';
  static const String pfOrderGetInfo = 'pforder/getInfo';
  static const String pfOrderSave = 'pforder/save';
  static const String pfOrderSign = 'pforder/sign';
  static const String pfOrderRetsign = 'pforder/retsign';
  static const String pfOrderDelBill = 'pforder/delBill';
  static const String pfOrderGeneratePfSell = 'pforder/generatePfSell';

  /// 批发销售
  static const String pfSellFindList = 'pfsell/findList';
  static const String pfSellGetInfo = 'pfsell/getInfo';
  static const String pfSellSave = 'pfsell/save';
  static const String pfSellSign = 'pfsell/sign';
  static const String pfSellRetsign = 'pfsell/retsign';
  static const String pfSellDelBill = 'pfsell/delBill';

  /// 订货汇总
  static const String pfSelectOrderStoreTotal = 'pfselectorder/findPfOrderStoreTotal';
  static const String pfSelectOrderTotal = 'pfselectorder/findPfOrderTotal';

  /// 应收款汇总
  static const String customerBillPayAbleSummary = 'finance/customerbill/getCustomerPayAbleSummary';

  /// 快速调价 API
  static const String productUpdateStoreprice = 'bi/product/UpdateStoreprice'; // 保存门店调价

  /// 新品申请 API
  static const String applyNewProGetList = 'bi/applynewpro/getApplyList'; // 新品申请列表
  static const String applyNewProUpdate = 'bi/applynewpro/updateApplynewPro'; // 新品申请操作(删除/撤回/审核/驳回)

  /// 常用功能设置 API
  static const String menuCommonGetMenuCommon = 'MenuCommon/getMenuCommon'; // 获取常用功能配置
  static const String menuCommonSaveMenuCommon = 'MenuCommon/saveMenuCommon'; // 保存常用功能配置

  /// 财务模块 API（对齐 Vue 项目实际接口地址）
  /// 供应商结算单 (purchasePlierpay)
  static const String financeSupplierPayGetList = 'finance/supplierpay/getList'; // 列表
  static const String financeSupplierPayGetInfo = 'finance/supplierpay/getinfo'; // 详情
  static const String financeSupplierPayAdd = 'finance/supplierpay/add'; // 新增
  static const String financeSupplierPayUpdate = 'finance/supplierpay/update'; // 修改
  static const String financeSupplierPaySign = 'finance/supplierpay/signSupplierPay'; // 审核
  static const String financeSupplierPayDelete = 'finance/supplierpay/delete'; // 删除
  static const String financeSupplierPayZf = 'finance/supplierpay/zfSupplierPay'; // 作废
  static const String financeSupplierPayGetSupplierBill =
      'finance/supplierpay/getSupplierBill'; // 获取供应商账单

  /// 客户结算单 (custPlierpay)
  static const String financeCustomerPayGetList = 'finance/customerset/findList'; // 列表
  static const String financeCustomerPayGetInfo = 'finance/customerset/getInfo'; // 详情
  static const String financeCustomerPayAdd = 'finance/customerset/add'; // 新增
  static const String financeCustomerPayUpdate = 'finance/customerset/update'; // 修改
  static const String financeCustomerPaySign = 'finance/customerset/sign'; // 审核
  static const String financeCustomerPayDel = 'finance/customerset/del'; // 删除
  static const String financeCustomerPayZf = 'finance/customerset/zfCustomerSet'; // 作废
  static const String financeCustomerPayGetCustomerBill =
      'finance/customerset/getCustomerBill'; // 获取客户账单

  /// 门店结算单 (storePlierpay)
  static const String financeStorePayGetList = 'finance/storepay/getList'; // 列表
  static const String financeStorePayGetInfo = 'finance/storepay/getinfo'; // 详情
  static const String financeStorePayAdd = 'finance/storepay/add'; // 新增
  static const String financeStorePayUpdate = 'finance/storepay/update'; // 修改
  static const String financeStorePaySign = 'finance/storepay/signStorePay'; // 审核
  static const String financeStorePayDelete = 'finance/storepay/delete'; // 删除
  static const String financeStorePayZf = 'finance/storepay/zfStorePay'; // 作废
  static const String financeStorePayGetStoreBill = 'finance/storepay/getStoreBill'; // 获取门店账单

  /// 费用收支单 (costRevenueExpenses)
  static const String financeCostRevenueGetList = 'finance/fee/payment/getList'; // 列表
  static const String financeCostRevenueGetInfo = 'finance/fee/payment/getinfo'; // 详情
  static const String financeCostRevenueAdd = 'finance/fee/payment/add'; // 新增
  static const String financeCostRevenueUpdate = 'finance/fee/payment/update'; // 修改
  static const String financeCostRevenueSign = 'finance/fee/payment/signFeePayment'; // 审核
  static const String financeCostRevenueFsign = 'finance/fee/payment/fsignFeePayment'; // 反审核
  static const String financeCostRevenueDel = 'finance/fee/payment/delete'; // 删除
  static const String feeitemGetList = 'bi/feeitem/getList'; // 收支项目列表

  /// 促销计划 API
  static const String promotionPlanFindList = 'pt/master/getfindListcp'; // 促销计划列表
  static const String promotionPlanGetInfo = 'pt/master/getmasterinfo'; // 促销计划详情
  static const String promotionPlanSave = 'pt/master/addorupdatecp'; // 保存/更新促销计划
  static const String promotionPlanSign = 'pt/master/toExaminecp'; // 审核/撤回/反审核
  static const String promotionPlanDelete = 'pt/master/delete'; // 删除促销计划

  /// 门店调价单 API
  static const String storeChangePriceFindList = 'mp/findList'; // 门店调价单列表
  static const String storeChangePriceGetInfo = 'mp/getInfo'; // 门店调价单详情
  static const String storeChangePriceSave = 'mp/save'; // 保存门店调价单
  static const String storeChangePriceSign = 'mp/sign'; // 审核/撤回门店调价单
  static const String storeChangePriceDelBill = 'mp/delBill'; // 删除门店调价单

  /// 标签打印 API
  static const String setLabelPrintFlow = 'app/labelprint/setLabelPrintFlow'; // 执行标签打印
  static const String getLabelBill = 'app/labelprint/getLabelBill'; // 获取单据列表
  static const String getLabelBillDetail = 'app/labelprint/getLabelBillDetail'; // 获取单据明细
  static const String getPrintSet = 'wxprint/getPrintSet'; // 获取打印设置（含蓝牙配置）
  static const String savePrintSet = 'wxprint/savePrintSet'; // 保存打印设置（含蓝牙配置）

  /// 商品分组 API
  static const String labelProductGroupFindList = 'labelproductgroup/findList'; // 商品分组列表
  static const String labelProductGroupGetInfo = 'labelproductgroup/getInfo'; // 商品分组详情
  static const String labelProductGroupSave = 'labelproductgroup/save'; // 保存商品分组
  static const String labelProductGroupDelete = 'labelproductgroup/delete'; // 删除商品分组

  /// 插件数据查询（付款方式/银行账户等）
  static const String pluginsGet = 'plugins/get';

  /// 插件参数设置（同步关联包装单位/规格等）
  static const String pluginsSetParam = 'plugins/setParam';

  /// 会员管理 API（对齐 boss 项目 subs/member/members）
  static const String vipInfoGetVipList = 'vipInfo/getVipList'; // 会员列表
  static const String vipInfoGetVipInfo = 'vipInfo/getVipInfo'; // 会员详情
  static const String vipInfoGetVipInfoOtherData = 'vipInfo/getVipInfoOtherData'; // 会员标签/副卡等附属数据
  static const String vipInfoAdd = 'vipInfo/add'; // 新增/编辑/售卡保存会员
  static const String vipInfoDelete = 'vipInfo/delete'; // 删除会员
  static const String vipInfoGetVipNo = 'vipInfo/getVipNo'; // 获取会员卡号
  static const String vipTypeGetVipTypeList = 'vipType/getVipTypeList'; // 会员分类列表
  static const String vipTypeGetVipTypeInfo = 'vipType/getVipTypeInfo'; // 会员分类详情（含付费规则）
  static const String labelSetGetLabelSetList = 'labelSet/getLabelSetList'; // 会员标签列表
  static const String vipSetGetVipMoreSetList = 'vipSet/getVipMoreSetList'; // 会员档案自定义扩展字段
  static const String vipInfoPointOperate = 'vipInfo/pointOperate'; // 积分冲减/积分转储值
  static const String vipInfoAddMoney = 'vipInfo/addMoney'; // 会员充值
  static const String vipInfoGetVipRechargeRule = 'vipInfo/getVipRechargeRule'; // 充值赠送规则
  static const String vipInfoPay = 'vipInfo/pay'; // 会员收款（会员卡结算）
}
