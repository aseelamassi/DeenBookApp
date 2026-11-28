import 'format.dart';
import 'api.dart';
import 'ledger.dart';
import 'weight_pricing.dart';

/// Local deterministic parser. It never saves a transaction or invents a price.
String voiceNormalize(String text) => digits(text.toLowerCase())
    .replaceAll(RegExp(r'[\u064b-\u065f\u0670ـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي').replaceAll('ة', 'ه')
    .replaceAll('٫', '.')
    .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064a.]+', unicode: true), ' ')
    .trim().replaceAll(RegExp(r'\s+'), ' ');

const _units = <String, num>{
  'صفر':0,'واحد':1,'واحده':1,'وحده':1,'اثنين':2,'اتنين':2,'اثنان':2,
  'تنين':2,'ثنين':2,'ثنتين':2,'ثلاث':3,'ثلاثه':3,'تلات':3,'تلاته':3,
  'اربع':4,'اربعه':4,'خمس':5,'خمسه':5,'ست':6,'سته':6,
  'سبع':7,'سبعه':7,'ثمان':8,'ثمانيه':8,'تمانيه':8,'تمان':8,
  'تسع':9,'تسعه':9,'عشر':10,'عشره':10,'احدعشر':11,'حدعش':11,'حداش':11,
  'اتناش':12,'اثناش':12,'تنعش':12,'ثلاثطعش':13,'تلتعش':13,'تلاتعش':13,
  'اربعطعش':14,'اربعتعش':14,'خمستعش':15,'خمستاش':15,
  'ستعش':16,'ستطعش':16,'سبعتعش':17,'سبعطعش':17,'تمنتعش':18,'ثمانتعش':18,'تسعتعش':19,'تسعطعش':19,
  'عشرين':20,'عشرون':20,'ثلاثين':30,'تلاتين':30,'اربعين':40,
  'خمسين':50,'ستين':60,'سبعين':70,'ثمانين':80,'تمانين':80,'تسعين':90,
  'ميه':100,'مايه':100,'مائه':100,'مئه':100,'مئتين':200,'ميتين':200,
  'الف':1000,'الفين':2000,'نص':0.5,'نصف':0.5,'ربع':0.25,
};

class _Number {
  const _Number(this.value, this.start, this.end);
  final num value;
  final int start, end;
}

num? _single(String token) => num.tryParse(token) ?? _units[token];

List<String> _tokens(String text) {
  final result = <String>[];
  for (var word in voiceNormalize(text).split(' ')) {
    if (word.isEmpty) continue;
    // Split common attached prepositions only for known numeric expressions.
    if (word.length > 1 && word.startsWith('و') &&
        _single(word) == null && (_single(word.substring(1)) != null ||
        RegExp(r'^(دفع|سدد|حول|اخذ|اشتري|الباقي|باقي)').hasMatch(word.substring(1)))) {
      result.add('و'); word = word.substring(1);
    }
    if (word.length > 1 && word.startsWith('ب') &&
        _single(word.substring(1)) != null) {
      result.add('ب'); word = word.substring(1);
    }
    result.add(word);
  }
  return result;
}
_Number? _readNumber(List<String> t, int start) {
  if (start >= t.length) return null;
  final a = _single(t[start]);
  if (a == null || !a.isFinite || a < 0) return null;
  var value = a;
  var end = start + 1;
  if (a is int && a >= 1 && a <= 9 && end < t.length &&
      ['ميه','مائه','مئه','الف'].contains(t[end])) {
    value *= _units[t[end]]!;
    end++;
  } else if (a >= 1 && a <= 9 && end < t.length &&
      ['عشر','عشره'].contains(t[end])) {
    value = 10 + a; end++;
  }
  while (end + 1 < t.length && t[end] == 'و') {
    final b = _single(t[end + 1]);
    if (b == null) break;
    // Compound cardinal numbers, e.g. خمسة وعشرين / مية وخمسين.
    if ((value >= 100 && b < 100) ||
        (value >= 1000 && b < 1000) ||
        (value >= 1 && value <= 9 && b >= 20 && b <= 90 && b % 10 == 0) ||
        (value >= 20 && value % 10 == 0 && b >= 1 && b <= 9)) {
      value += b; end += 2;
    } else { break; }
  }
  return _Number(value, start, end);
}
List<_Number> _numbers(List<String> t) {
  final out = <_Number>[];
  for (var i = 0; i < t.length;) {
    final n = _readNumber(t,i);
    if (n == null) { i++; } else {out.add(n); i = n.end;}
  }
  return out;
}
const _currency = {'شيكل','شواكل','شيقل','ش','شيكلات'};
const _pay = {'دفع','دفعلي','دفعله','دفعت','دفعتله','دفعنا','سدد','سددلي',
  'سددت','سددتله','عطاني','اعطاني','اعطيت','اعطيته','عطيته','قبضت',
  'حول','حوللي','حولت','بعتلي','وصلني','سداد','دفعتلو'};
const _purchase = {'اشترى','اشتري','اشتريت','اخذ','اخدت','اخذت','اخد','خد',
  'خذ','جبت','باع','بعت','بعته','سجل','سجلي','حط','حطلي','دين','مشتريات','فاتوره','بضاعه'};
const _supplierPay = {'دفعت','دفعتله','سددت','سددتله','اعطيت','اعطيته','عطيته','حولت','دفعتلو'};
const _weightUnits = {'كيلو','كغم','كجم','كيلوغرام','كيلوجرام','كيلوين','كيلوان',
  'غرام','جرام','غرامات','جرامات'};
const _pieceUnits = {'حبه','حبتين','حبات','قطعه','قطعتين','قطع','علبه','علبتين',
  'علب','كيس','كيسين','اكياس','زجاجه','زجاجتين','عبوه','عبوتين','كرتونه',
  'كرتونتين','كراتين','كرتون','صندوق','صندوقين','شوال','شوالين','طرد','طردين'};
const _dual = {'كيلوين','كيلوان','حبتين','قطعتين','علبتين','كيسين','زجاجتين',
  'عبوتين','كرتونتين','صندوقين','شوالين','طردين'};
bool _matches(String token,String value) =>
  token == value || token == 'و$value' || token == 'ال$value' || token == 'وال$value';
bool _has(List<String> t, Set<String> values) => t.any((v)=>values.any((x)=>_matches(v,x)));

class _Entity {
  const _Entity(this.row,this.start,this.end,this.ambiguous);
  final Json row;
  final int start,end;
  final bool ambiguous;
}
List<_Entity> _entities(List<String> t,List<Json> rows,{bool parties=false}) {
  final result = <_Entity>[];
  for (var i=0;i<t.length;i++) {
    final candidates = <(Json,int)>[];
    for(final row in rows) {
      final name=voiceNormalize('${row['name'] ?? ''}').split(' ');
      if(name.first.isEmpty) continue;
      final names=<List<String>>[name];
      if(parties) {
        final nick=voiceNormalize('${row['nickname'] ?? ''}');
        if(nick.isNotEmpty) names.add(nick.split(' '));
        if(name.length>1) names.add([name.first]);
      }
      for(final alias in names) {
        if(i+alias.length>t.length) continue;
        var ok=true;
        for(var k=0;k<alias.length;k++) {
          if(!_matches(t[i+k],alias[k])) {ok=false;break;}
        }
        if(ok) candidates.add((row,alias.length));
      }
    }
    if(candidates.isEmpty) continue;
    candidates.sort((a,b)=>b.$2.compareTo(a.$2));
    final longest=candidates.first.$2;
    final best=candidates.where((x)=>x.$2==longest).toList();
    final ids=best.map((x)=>x.$1['id']).toSet();
    result.add(_Entity(best.first.$1,i,i+longest,ids.length>1));
    i+=longest-1;
  }
  return result;
}


String _supplierUnit(String token,bool weight,String fallback) {
  if(weight || _weightUnits.contains(token))return 'كغم';
  if(['كرتونه','كرتونتين','كراتين','كرتون'].contains(token))return 'كرتونة';
  if(['صندوق','صندوقين'].contains(token))return 'صندوق';
  if(['شوال','شوالين'].contains(token))return 'شوال';
  if(['طرد','طردين'].contains(token))return 'طرد';
  if(['علبه','علبتين','علب'].contains(token))return 'علبة';
  if(['كيس','كيسين','اكياس'].contains(token))return 'كيس';
  return token.isEmpty?fallback:'قطعة';
}


int _editDistance(String a,String b) {
  var prev=List<int>.generate(b.length+1,(i)=>i);
  for(var i=0;i<a.length;i++){
    final next=<int>[i+1];
    for(var j=0;j<b.length;j++){
      final values=[next[j]+1,prev[j+1]+1,prev[j]+(a[i]==b[j]?0:1)];
      next.add(values.reduce((a,b)=>a<b?a:b));
    }
    prev=next;
  }
  return prev.last;
}
List<String> _closePartyNames(List<String> tokens,List<Json> rows){
  final found=<String>[];
  for(final row in rows){
    final name=voiceNormalize('${row['name']??''}').split(' ').first;
    if(name.length<4)continue;
    if(tokens.any((word)=>word.length>=4 && (word.length-name.length).abs()<=1 &&
        _editDistance(word,name)==1)){
      found.add('${row['name']}');
    }
    if(found.length>=4)break;
  }
  return found;
}

class VoiceDraft {
  const VoiceDraft({required this.transcript,required this.kind,required this.supplier,
    required this.party,required this.lines,required this.totalCents,
    required this.paidCents,required this.method,required this.waiting,
    required this.warnings});
  final String transcript, kind, method;
  final bool supplier,waiting;
  final Json? party;
  final List<InvoiceLine> lines;
  final int? totalCents, paidCents;
  final List<String> warnings;
}

/// Supports explicitly named accounts, catalog products, Palestinian number
/// variants, quantities/weights and payment clauses. Unknown/ambiguous inputs
/// remain editable; a warning is never treated as a successful extraction.
VoiceDraft parseVoiceCommand(String text,{required List<Json> customers,
  required List<Json> suppliers,required List<Json> products,
  Json? fixedParty,String? fixedKind,bool? fixedSupplier,bool modern=true}) {
  final t=_tokens(text);
  final warnings=<String>[];
  final nums=_numbers(t);
  if (_has(t,{'امبارح','مبارح','امس','اول','بكره','بكرا'})) {
    warnings.add('التاريخ يُحفظ وفق إعدادات الحركة الحالية؛ راجع التاريخ المذكور في الأمر.');
  }
  final pIndex=t.indexWhere((v)=>_pay.any((x)=>_matches(v,x)));
  final hasPurchase=_has(t,_purchase);
  final hasPayment=pIndex>=0;
  if (hasPayment && pIndex>0 && ['ما','مش','لم','بدون','غير'].contains(t[pIndex-1])) {
    warnings.add('ورد نفي للدفع؛ تحقق من نوع الحركة ومبلغ الدفعة.');
  }
  final customerMatches=_entities(t,customers,parties:true);
  final supplierMatches=_entities(t,suppliers,parties:true);
  final incoming=_has(t,{'اشتريت','اخذت','اخدت','جبت'}) &&
      _has(t,{'من','المورد','مورد'});
  final supplier= fixedSupplier ?? (incoming || _has(t,{'مورد','المورد'}) ||
      _has(t,_supplierPay) || (supplierMatches.isNotEmpty && customerMatches.isEmpty));
  final returnRequested=_has(t,{'مرتجع','ارجع','رجع','رجعت','رد'});
  final kind=fixedKind ?? (returnRequested ? 'Return' :
      hasPurchase && (!hasPayment || (t.indexWhere((v)=>_purchase.any((x)=>_matches(v,x)))<pIndex))
      ? (supplier?'Purchase':'Debt') : hasPayment?'Payment':(supplier?'Purchase':'Debt'));
  if(fixedKind==null && !hasPurchase && !hasPayment && !returnRequested) {
    warnings.add('لم يتضح نوع الحركة؛ راجع النوع قبل المتابعة.');
  }
  if(fixedKind!=null && ((kind=='Payment' && hasPurchase && !hasPayment) ||
      (kind!='Payment' && !hasPurchase && hasPayment))) {
    warnings.add('الكلام قد يصف نوع حركة مختلفًا عن الشاشة الحالية.');
  }
  final hits=supplier?supplierMatches:customerMatches;
  Json? party=fixedParty;
  if(party==null) {
    if(hits.length==1 && !hits.first.ambiguous) {
      party=hits.first.row;
    } else {
      warnings.add(hits.isEmpty?'لم أجد الحساب؛ اختره يدويًا.':'اسم الحساب غير محدد أو مكرر؛ اختر الحساب يدويًا.');
      if(hits.isEmpty){
        final suggestions=_closePartyNames(t,supplier?suppliers:customers);
        if(suggestions.isNotEmpty)warnings.add('أسماء مشابهة للمراجعة فقط: ${suggestions.join('، ')}');
      }
    }
  } else if(hits.any((h)=>h.ambiguous || h.row['id']!=party!['id'])) {
    warnings.add('ورد اسم حساب مختلف أو مكرر؛ تحقق من الحساب المفتوح.');
  }
  if(fixedSupplier==null && customerMatches.isNotEmpty && supplierMatches.isNotEmpty &&
      !incoming && !_has(t,{'مورد','المورد'}) && !_has(t,_supplierPay)) {
    party=null; warnings.add('الاسم موجود بين الزبائن والموردين؛ راجع نوع الحساب.');
  }
  final invoice=kind=='Debt'||kind=='Purchase';
  final entries=<InvoiceLine>[];
  final used=<int>{};
  final productsFound=invoice && modern?_entities(t,products):<_Entity>[];
  if (invoice && modern && supplier) {
    // Independent wholesale items: support names absent from the retail catalog
    // in the explicit pattern «3 كراتين زيت بسعر 20» / «كيلو سكر بسعر 5».
    for (var i=0;i<t.length-2;i++) {
      var unit=t[i];
      if(unit.startsWith('و') && (_weightUnits.contains(unit.substring(1)) || _pieceUnits.contains(unit.substring(1))))unit=unit.substring(1);
      if(!_weightUnits.contains(unit)&&!_pieceUnits.contains(unit))continue;
      var end=i+1;
      while(end<t.length && end-i<=6 && t[end]!='بسعر' &&
          !_pay.contains(t[end]) && _single(t[end])==null &&
          !_weightUnits.contains(t[end]) && !_pieceUnits.contains(t[end])) {
        end++;
      }
      if(end<=i+1 || end>=t.length || t[end]!='بسعر')continue;
      if(productsFound.any((h)=>h.start>=i+1 && h.start<end))continue;
      if(hits.any((h)=>h.start>=i+1 && h.start<end))continue;
      final name=t.sublist(i+1,end).join(' ');
      final weight=_weightUnits.contains(unit);
      productsFound.add(_Entity(<String,dynamic>{
        'id':'voice-$i','name':name,'unit':weight?'كغم':unit,
        'pricingMode':weight?'Weight':'Piece','salePrice':0
      },i+1,end,false));
    }
    productsFound.sort((a,b)=>a.start.compareTo(b.start));
  }
  final itemHits=productsFound.where((h)=>!hits.any((a)=>h.start<a.end && h.end>a.start) &&
    (!hasPayment || kind=='Payment' || h.start<pIndex)).toList();
  int? money(_Number n) => n.value>0 && n.value<=999999999 &&
      (n.value*100-(n.value*100).round()).abs()<0.00001 ? (n.value*100).round():null;
  bool marked(_Number n) => (n.start>0 && {'ب','بمبلغ','بقيمه','بسعر','مبلغ','المبلغ','الاجمالي','اجمالي','المجموع'}.contains(t[n.start-1])) ||
      (n.end<t.length && _currency.contains(t[n.end]));
  bool quantityNumber(_Number n)=> n.end<t.length && (_weightUnits.contains(t[n.end])||_pieceUnits.contains(t[n.end]));
  int? paid;
  if(invoice && hasPayment) {
    final candidates=nums.where((n)=>n.start>pIndex && !quantityNumber(n)).toList();
    if(candidates.length==1) {paid=money(candidates.first);used.add(candidates.first.start);}
    else if(candidates.isNotEmpty && candidates.first.start==pIndex+1 &&
        _has(t.sublist(candidates.first.end),{'باقي','الباقي'})) {
      paid=money(candidates.first); used.add(candidates.first.start);
      for(final n in candidates.skip(1)) {used.add(n.start);}
    }
    if(paid==null) warnings.add('لم يتضح مبلغ الدفعة؛ أدخله يدويًا.');
  }
  for(var i=0;i<itemHits.length;i++) {
    final h=itemHits[i];
    if(h.ambiguous) {warnings.add('اسم صنف مكرر: ${h.row['name']}؛ اختره يدويًا.');continue;}
    final previous=i==0?0:itemHits[i-1].end;
    final next=i+1==itemHits.length?(hasPayment?pIndex:t.length):itemHits[i+1].start;
    final product=h.row;
    final isWeight=soldByWeight(product);
    final price=amountCents(product['salePrice']);
    var quantity=0;
    var unitToken='';
    _Number? qty;
    if(h.start>previous) {
      var before=t[h.start-1];
      if(before.startsWith('و') && (_weightUnits.contains(before.substring(1)) || _pieceUnits.contains(before.substring(1)))) before=before.substring(1);
      if(_weightUnits.contains(before)||_pieceUnits.contains(before)) {
        unitToken=before;
        final q=nums.where((n)=>n.end==h.start-1 && !used.contains(n.start)).lastOrNull;
        qty=q;
        final value=q?.value??(_dual.contains(before)?2:1);
        quantity=(value*(_weightUnits.contains(before)&&before.contains('رام')&&!before.contains('كيلو')?1:1000)).round();
      } else {
        qty=nums.where((n)=>n.end==h.start && !used.contains(n.start) && !marked(n)).lastOrNull;
        if(qty!=null) quantity=(qty.value*1000).round();
      }
    }
    if(qty!=null) used.add(qty.start);
    final after=nums.where((n)=>n.start>=h.end && n.end<=next &&
      !used.contains(n.start) && marked(n) && !quantityNumber(n) &&
      n.start>0 && ['ب','بمبلغ','بقيمه','بسعر'].contains(t[n.start-1])).toList();
    final explicit=after.length==1?money(after.first):null;
    if(after.length>1) warnings.add('أكثر من سعر للصنف ${product['name']}؛ راجع المبلغ.');
    if(supplier) {
      // Supplier invoice is independent of the retail catalog. Only explicit
      // wholesale unit prices are accepted, never infer from retail prices.
      if(quantity>0 && explicit!=null && t[after.first.start-1]=='بسعر') {
        used.add(after.first.start);
        if (['كرتونه','كرتونتين','كراتين','كرتون','صندوق','صندوقين','شوال','شوالين','طرد','طردين'].contains(unitToken)) {
          warnings.add('راجع عدد العبوات في ${product['name']}؛ لا يمكن استنتاج حجم الكرتونة.');
        }
        entries.add(InvoiceLine(id:'voice-${h.start}',name:'${product['name']}',
          unit:_supplierUnit(unitToken,isWeight,'${product['unit']}'),
          price:explicit,quantity:quantity));
      } else {
        warnings.add('راجع كمية وسعر الجملة للصنف ${product['name']} في الفاتورة.');
      }
      continue;
    }
    if(price<=0) {warnings.add('لا يوجد سعر بيع صالح للصنف ${product['name']}.');continue;}
    if(unitToken.isNotEmpty && (isWeight!=_weightUnits.contains(unitToken))) {
      warnings.add('وحدة الصنف ${product['name']} لا تطابق وحدة البيع.');continue;
    }
    var byAmount=false;
    if(quantity==0 && explicit!=null && isWeight) {
      quantity=gramsForAmount(price,explicit);
      if(totalForGrams(price,quantity)!=explicit) {
        warnings.add('قيمة ${product['name']} لا تطابق الوزن بعد التقريب.');
      }
      byAmount=true;
    }
    if(quantity<=0 || (!isWeight && quantity%1000!=0)) {
      warnings.add('حدد كمية الصنف ${product['name']} يدويًا.');continue;
    }
    final line=InvoiceLine.product(product,false).withQuantity(quantity).withPricingEntry(byAmount:byAmount);
    if(explicit!=null) {
      used.add(after.first.start);
      final expected=t[after.first.start-1]=='بسعر'?line.price:line.total;
      if(expected!=explicit) warnings.add('سعر أو إجمالي ${product['name']} المذكور يختلف عن السعر المسجل.');
    }
    entries.add(line);
  }
  final candidateTotals=nums.where((n)=>!used.contains(n.start)&& !quantityNumber(n) &&
    (!invoice || !hasPayment || n.start<pIndex) &&
    (marked(n) || (entries.isEmpty && nums.length==1) ||
    (kind=='Payment' && n.start>pIndex))).toList();
  int? explicitTotal;
  if(candidateTotals.length==1) explicitTotal=money(candidateTotals.first);
  if(candidateTotals.length>1) warnings.add('ورد أكثر من مبلغ إجمالي محتمل؛ راجع المبلغ.');
  final sum=entries.fold<int>(0,(s,l)=>s+l.total);
  if(entries.isNotEmpty && explicitTotal!=null && sum!=explicitTotal) {
    warnings.add('الإجمالي المذكور لا يطابق مجموع الأصناف؛ راجع الفاتورة.');
  }
  if(invoice && nums.any((n)=>quantityNumber(n)&&!used.contains(n.start))) {
    warnings.add('هناك كمية لم تُربط بصنف؛ راجع كل الأصناف المذكورة.');
  }
  if (_has(t,{'خصم','خصمت','تخفيض','خصمله'})) {
    warnings.add('ورد خصم في الكلام؛ أدخل قيمة الخصم يدويًا في النموذج إذا لزم.');
  }
  if(itemHits.length!=entries.length) warnings.add('بعض الأصناف لم تكتمل؛ أضفها أو صححها يدويًا.');
  if(invoice && _has(t,{..._weightUnits,..._pieceUnits}) && entries.isEmpty) {
    warnings.add('ذُكرت كميات أو أصناف لم يتم تعبئتها؛ راجع التفاصيل يدويًا.');
  }
  final total=entries.isNotEmpty?sum:explicitTotal;
  if(total==null||total<=0) warnings.add('لم يتضح المبلغ؛ أدخله يدويًا.');
  if(paid!=null && total!=null && paid>total) warnings.add('المبلغ المدفوع أكبر من الإجمالي؛ راجع القيم.');
  var method='Cash';
  if(_has(t,{'بنك','البنك','بنكي','عالبنك','بالبنك'})) method='Bank';
  else if(_has(t,{'جوال'}) && _has(t,{'باي','pay'})) method='JawwalPay';
  else if(_has(t,{'بال'}) && _has(t,{'باي','pay'})) method='PalPay';
  else if(_has(t,{'حول','حوللي','حولت','حواله','تحويل'})) {
    warnings.add('حدد وسيلة الحوالة من النموذج؛ لم تُذكر بوضوح.');
  }
  final waiting=kind=='Payment'&&!supplier&&method!='Cash' &&
    (_has(t,{'معلقه','انتظار'})||voiceNormalize(text).contains('لم تصل')||
    voiceNormalize(text).contains('ما وصل')||voiceNormalize(text).contains('لسه ما وصل'));
  return VoiceDraft(transcript:text,kind:kind,supplier:supplier,party:party,
    lines:entries,totalCents:total,paidCents:paid,method:method,waiting:waiting,
    warnings:warnings.toSet().toList());
}
