import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

class SelectStorePage extends StatelessWidget {
  const SelectStorePage({super.key, this.onTap});
  final void Function(Map<String, dynamic>)? onTap;

  /// 读取登录门店 JSON 的字符串字段（对齐 Vue cookie store 对象，如 supflag/custflag/spid）
  static String loginStoreField(String key) {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap[key]?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  static Future<Map<String, dynamic>?> _fetchData(
    String searchText,
    int page, {
    String? areaid,
    List<int>? storetypes,
    bool sendStoretypes = true,
    bool isLs = false,
    String? supflag,
    String? custflag,
    String? stopflag,
    String? psselecttype,
    String? nosidsflag,
    String? nostoreid,
    List<dynamic>? sids,
    String? applysid,
    String? insid,
    String? outsid,
    String? psstoreflag,
    String? psstoreid,
    List<dynamic>? parentIds,
    String? pscounterflag,
  }) {
    final params = <String, dynamic>{
      'cond': searchText,
      'is_page': 1,
      'page': page,
      'pagesize': 20,
    };
    // 对齐 Vue comPages/selectStore：storetypes 由调用方 mergData 决定，未传则不发送
    if (sendStoretypes) params['storetypes'] = storetypes ?? [0, 1, 2, 3];
    if (areaid != null && areaid != '0') params['areaid'] = areaid;
    if (supflag != null && supflag.isNotEmpty) params['supflag'] = supflag;
    if (custflag != null && custflag.isNotEmpty) params['custflag'] = custflag;
    if (stopflag != null && stopflag.isNotEmpty) params['stopflag'] = stopflag;
    if (psselecttype != null && psselecttype.isNotEmpty) params['psselecttype'] = psselecttype;
    if (nosidsflag != null && nosidsflag.isNotEmpty) params['nosidsflag'] = nosidsflag;
    if (nostoreid != null && nostoreid.isNotEmpty) params['nostoreid'] = nostoreid;
    if (sids != null) params['sids'] = sids;
    if (applysid != null && applysid.isNotEmpty) params['applysid'] = applysid;
    // 对齐 Vue comPages/selectStore mergData 透传：配送业务机构联动参数
    if (insid != null && insid.isNotEmpty) params['insid'] = insid;
    if (outsid != null && outsid.isNotEmpty) params['outsid'] = outsid;
    if (psstoreflag != null && psstoreflag.isNotEmpty) params['psstoreflag'] = psstoreflag;
    if (psstoreid != null && psstoreid.isNotEmpty) params['psstoreid'] = psstoreid;
    // 对齐 Vue comPages/selectStore mergData 透传：按父机构过滤（配退收货退货门店按配送中心过滤）
    if (parentIds != null) params['parentIds'] = parentIds;
    // 对齐 Vue store-form-item mergeData：总店作为配送中心时的仓库联动标志
    if (pscounterflag != null && pscounterflag.isNotEmpty) params['pscounterflag'] = pscounterflag;
    // 对齐 Vue comPages/selectStore 组件自动注入（在 mergData 之后展开，优先级更高）：
    // 配送中心（storetype==3）且非总店且非 isLs → selltypesidsflag: 1
    // 区域中心（storetype==4）或总店（id==spid）→ nosidsflag: 1
    final storetype = loginStoreField('storetype');
    final storeId = loginStoreField('id');
    final storeSpid = loginStoreField('spid');
    final isPsStore = storetype == '3';
    final isQyStore = storetype == '4';
    final isStore = storeId.isNotEmpty && storeId == storeSpid;
    if (isPsStore && !isStore && !isLs) params['selltypesidsflag'] = '1';
    if (isQyStore || isStore) params['nosidsflag'] = '1';
    return request(HttpApi.storeGetList, params).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  /// 对齐后台 cgother/cgothercd edit.vue 配送中心 store-form-item 的 applysid 计算：
  /// `!isPsStore && (lsPsCenterRangeFlag || !isStore) ? form.bsid : ''`
  /// （非配送中心登录且（连锁配送中心范围开关开启或非总店）时，按当前收货机构 bsid 过滤其下属配送中心）
  static String psCenterApplysid(dynamic bsid) {
    final isPsStore = loginStoreField('storetype') == '3';
    final storeId = loginStoreField('id');
    final isStore = storeId.isNotEmpty && storeId == loginStoreField('spid');
    bool rangeFlag = false;
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        rangeFlag = cfg['lsPsCenterRangeFlag']?.toString() == '1';
      }
    } catch (_) {}
    if (!isPsStore && (rangeFlag || !isStore)) return bsid?.toString() ?? '';
    return '';
  }

  /// 以底部抽屉方式打开机构选择
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    bool showAll = false,
    String? initialSelectedId,
    String? areaid,
    String title = '选择机构',
    List<int>? storetypes,
    bool sendStoretypes = true,
    bool isLs = false,
    String? supflag,
    String? custflag,
    String? stopflag,
    String? psselecttype,
    String? nosidsflag,
    String? nostoreid,
    List<dynamic>? sids,
    String? applysid,
    String? insid,
    String? outsid,
    String? psstoreflag,
    String? psstoreid,
    List<dynamic>? parentIds,
    String? pscounterflag,
  }) {
    return CommonSelectSheet.show(
      context,
      title: title,
      searchHint: '输入机构名称/编码',
      fetchData: (String searchText, int page) => _fetchData(
        searchText,
        page,
        areaid: areaid,
        storetypes: storetypes,
        sendStoretypes: sendStoretypes,
        isLs: isLs,
        supflag: supflag,
        custflag: custflag,
        stopflag: stopflag,
        psselecttype: psselecttype,
        nosidsflag: nosidsflag,
        nostoreid: nostoreid,
        sids: sids,
        applysid: applysid,
        insid: insid,
        outsid: outsid,
        psstoreflag: psstoreflag,
        psstoreid: psstoreid,
        parentIds: parentIds,
        pscounterflag: pscounterflag,
      ),
      showAll: showAll,
      initialSelectedId: initialSelectedId,
      mapResult: (item) => mapStoreResult(item),
    );
  }

  /// 统一机构结果映射：附带冷热/服务配送中心字段（对齐 Vue pick(e, ['ntsid','coldsid','fwsid'])）
  static Map<String, dynamic> mapStoreResult(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    return {
      'storeid': item['id']?.toString() ?? '',
      'storename': name,
      'storetype': item['storetype']?.toString() ?? '',
      'ntsid': item['ntsid']?.toString() ?? '',
      'coldsid': item['coldsid']?.toString() ?? '',
      'fwsid': item['fwsid']?.toString() ?? '',
      'allowflag': item['allowflag']?.toString() ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CommonSelectSheet(
        title: '选择机构',
        searchHint: '输入机构名称/编码',
        fetchData: _fetchData,
        mapResult: (item) {
          final selected = mapStoreResult(item);
          onTap?.call(selected);
          return selected;
        },
      ),
    );
  }
}
