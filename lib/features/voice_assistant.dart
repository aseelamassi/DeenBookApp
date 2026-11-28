import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/api.dart';
import '../core/ledger.dart';
import '../core/session.dart';
import '../core/voice_command.dart';
import '../ui/theme.dart';

/// Voice is only a draft: the normal transaction screen owns validation/save.
Future<VoiceDraft?> showVoiceAssistant(BuildContext context,{
  Json? fixedParty,String? fixedKind,bool? fixedSupplier,
}) {
  final session=Scope.of(context);
  return showDialog<VoiceDraft>(
    context:context,
    builder:(_)=>_VoiceAssistant(api:session.api,modern:session.ledgerV2,
      fixedParty:fixedParty,fixedKind:fixedKind,fixedSupplier:fixedSupplier),
  );
}
class _VoiceAssistant extends StatefulWidget {
  const _VoiceAssistant({required this.api,required this.modern,
    this.fixedParty,this.fixedKind,this.fixedSupplier});
  final Api api;
  final bool modern;
  final Json? fixedParty;
  final String? fixedKind;
  final bool? fixedSupplier;
  @override
  State<_VoiceAssistant> createState()=>_VoiceAssistantState();
}
class _VoiceAssistantState extends State<_VoiceAssistant> {
  final text=TextEditingController();
  final speech=SpeechToText();
  bool listening=false,loading=false,starting=false,accepted=false;
  String? status;
  String operation='auto';
  VoiceDraft? draft;
  @override
  void dispose(){
    speech.cancel();
    text.dispose();
    super.dispose();
  }
  void invalidate(){
    setState((){draft=null;accepted=false;});
  }
  Future<void> toggle() async {
    if(listening){await speech.stop();if(mounted)setState(()=>listening=false);return;}
    if(starting||loading)return;
    setState((){starting=true;status=null;draft=null;accepted=false;});
    try{
      final ready=await speech.initialize(
        onStatus:(s){if(mounted)setState(()=>listening=s=='listening');},
        onError:(_){if(mounted)setState((){listening=false;
          status='تعذّر التعرف على الصوت. يمكنك كتابة الأمر أو إعادة المحاولة.';});},
      );
      if(!mounted)return;
      if(!ready){setState(()=>status='اسمح بالميكروفون والتعرف على الكلام من إعدادات الجهاز.');return;}
      final locales=await speech.locales();
      if(!mounted)return;
      final arabic=locales.where((x)=>x.localeId.toLowerCase().startsWith('ar')).toList();
      if(arabic.isEmpty){
        setState(()=>status='لم تتوفر لغة عربية للتعرف الصوتي على الجهاز. يمكنك كتابة الأمر.');
        return;
      }
      final locale=arabic.where((x)=>RegExp(r'^ar[-_](ps|jo)$',caseSensitive:false).hasMatch(x.localeId)).firstOrNull ?? arabic.first;
      await speech.listen(onResult:(r){
        if(!mounted)return;
        setState((){
          text.text=r.recognizedWords;
          text.selection=TextSelection.collapsed(offset:text.text.length);
          draft=null;accepted=false;
          if(r.finalResult) listening=false;
        });
      },listenOptions:SpeechListenOptions(localeId:locale.localeId,
        listenMode:ListenMode.dictation,partialResults:true,onDevice:widget.api.isOffline));
    }catch(_){
      if(mounted)setState(()=>status='الإدخال الصوتي غير متاح حاليًا. اكتب الأمر يدويًا.');
    }finally{
      if(mounted)setState(()=>starting=false);
    }
  }
  Future<(List<Json>,bool)> catalog(String path) async{
    final rows=<String,Json>{};
    var partial=false;
    try{
      // The same API/cache used by the existing account and product screens.
      for(var page=1;page<=30;page++){
        final response=await widget.api.get(path,query:{
          'page':page,'size':100,
          if(path!='/api/products')'sort':'name',
        });
        final items=response['items'] as List? ?? [];
        for(final item in items){
          if(item is Map && item['id']!=null){
            rows['${item['id']}']=Map<String,dynamic>.from(item);
          }
        }
        final total=response['total'];
        if(response['offlinePartial']==true)partial=true;
        if(items.isEmpty || (total is num ? rows.length>=total : items.length<100))break;
        if(page==30)partial=true;
      }
    }catch(_){partial=true;}
    return (rows.values.toList(),partial);
  }
  Future<void> analyze() async{
    if(loading||starting||listening||text.text.trim().isEmpty)return;
    final transcript=text.text.trim();
    final shop=widget.api.savedShopId;
    final user=widget.api.verifiedUserId;
    setState((){loading=true;draft=null;accepted=false;status=null;});
    try{
      final lists=await Future.wait([
        if(widget.fixedSupplier!=true)
          catalog('/api/customers') else Future.value((<Json>[],false)),
        if(widget.fixedSupplier!=false)
          catalog('/api/suppliers') else Future.value((<Json>[],false)),
        if(widget.modern) catalog('/api/products') else Future.value((<Json>[],false)),
      ]);
      if(!mounted)return;
      if(shop!=widget.api.savedShopId||user!=widget.api.verifiedUserId){
        setState(()=>status='تغيّر الحساب. أغلق المساعد وافتحه من جديد.');
        return;
      }
      final result=parseVoiceCommand(transcript,
        customers:lists[0].$1,suppliers:lists[1].$1,products:lists[2].$1,
        fixedParty:widget.fixedParty,
        fixedKind:widget.fixedKind ?? (operation=='auto'?null:operation.split(':').last),
        fixedSupplier:widget.fixedSupplier ?? (operation=='auto'?null:operation.startsWith('supplier:')),
        modern:widget.modern);
      if(lists.any((l)=>l.$2)){
        result.warnings.add('قد تكون بعض الحسابات أو الأصناف غير متوفرة محليًا. تحقق من الاختيارات.');
      }
      // Always require acknowledgement for warnings, even if a value exists.
      if(mounted)setState(()=>draft=result);
    }catch(_){
      if(mounted)setState(()=>status='تعذّر تحليل الأمر؛ عدّل النص أو أدخل الحركة يدويًا.');
    }finally{if(mounted)setState(()=>loading=false);}
  }
  String label(VoiceDraft d)=>d.kind=='Payment'?
    (d.supplier?'سداد مورد':'قبض دفعة زبون'):d.kind=='Return'?
    (d.supplier?'مرتجع مورد':'مرتجع زبون'):d.supplier?'فاتورة مورد':'تسجيل مشتريات (دين)';
  @override
  Widget build(BuildContext context){
    final d=draft;
    return AlertDialog(
      title:const Text('المساعد الصوتي'),
      content: SizedBox(width:420,child:SingleChildScrollView(child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,
        children:[
          const Text('احكي بطريقتك، أو اكتب الأمر. لن تُحفظ أي حركة قبل مراجعتها وتأكيدها.'),
          const SizedBox(height:12),
          Center(child:FilledButton.icon(
            onPressed:loading||starting?null:toggle,
            icon:Icon(listening?Icons.stop_circle_outlined:Icons.mic_none),
            label:Text(listening?'إيقاف التسجيل':starting?'جارٍ تشغيل الميكروفون':'اضغط وتكلم'),
          )),
          const SizedBox(height:12),
          TextField(key:const Key('voice-command-text'),controller:text,
            enabled:!loading&&!listening&&!starting,maxLines:4,minLines:2,
            maxLength:600,onChanged:(_)=>invalidate(),
            decoration:const InputDecoration(labelText:'الأمر الصوتي',
              hintText:'يوسف أخذ نص كيلو جبنة ودفع خمسة شيكل')),
          if(widget.fixedKind==null)
            DropdownButtonFormField<String>(
              initialValue:operation,
              isExpanded:true,
              decoration:const InputDecoration(labelText:'نوع الحركة'),
              items:const [
                DropdownMenuItem(value:'auto',child:Text('تحديد تلقائي')),
                DropdownMenuItem(value:'customer:Debt',child:Text('مشتريات زبون')),
                DropdownMenuItem(value:'customer:Payment',child:Text('دفعة زبون')),
                DropdownMenuItem(value:'supplier:Purchase',child:Text('فاتورة مورد')),
                DropdownMenuItem(value:'supplier:Payment',child:Text('دفعة مورد')),
                DropdownMenuItem(value:'customer:Return',child:Text('مرتجع زبون')),
                DropdownMenuItem(value:'supplier:Return',child:Text('مرتجع مورد')),
              ],
              onChanged:loading||listening||starting?null:(value){
                setState((){operation=value??'auto';draft=null;accepted=false;});
              },
            ),
          const SizedBox(height:8),
          if(status!=null) Text(status!,style:const TextStyle(color:Colors.red)),
          OutlinedButton.icon(key:const Key('voice-analyze'),
            onPressed:loading||listening||starting||text.text.trim().isEmpty?null:analyze,
            icon:loading?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_fix_high),
            label:Text(loading?'جارٍ مطابقة الحسابات والأصناف':'تحليل الأمر')),
          if(d!=null)...[
            const Divider(),
            Text(label(d),style:const TextStyle(fontWeight:FontWeight.bold,color:navy)),
            Text('الحساب: ${d.party?['name']??'يحتاج اختيارًا'}'),
            Text('المبلغ: ${d.totalCents==null?'غير محدد':'${decimalMoney(d.totalCents!)} ₪'}'),
            if(d.paidCents!=null)Text('الدفعة: ${decimalMoney(d.paidCents!)} ₪'),
            if(d.waiting)const Text('الحوالة بانتظار التأكيد'),
            for(final line in d.lines) Text('${line.name} · ${quantityText(line.quantity)} ${line.unit} · ${decimalMoney(line.total)} ₪'),
            if(d.warnings.isNotEmpty)...[
              const SizedBox(height:8),
              const Text('تحتاج مراجعة',style:TextStyle(fontWeight:FontWeight.bold,color:Colors.deepOrange)),
              for(final warning in d.warnings) Padding(padding:const EdgeInsets.only(bottom:4),child:Text('• $warning')),
              CheckboxListTile(contentPadding:EdgeInsets.zero,value:accepted,
                onChanged:(v)=>setState(()=>accepted=v??false),
                title:const Text('سأراجع وأكمل البيانات الناقصة في النموذج.')),
            ],
          ],
        ],
      ))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء')),
        FilledButton(key:const Key('voice-apply'),
          onPressed:d==null||loading||listening||(d.warnings.isNotEmpty&&!accepted)
              ?null:()=>Navigator.pop(context,d),
          child:const Text('تعبئة نموذج الحركة')),
      ],
    );
  }
}
