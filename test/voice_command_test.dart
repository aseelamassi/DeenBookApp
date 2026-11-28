import 'package:deenbook/core/api.dart';
import 'package:deenbook/core/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final customers=<Json>[
    {'id':'y','name':'يوسف أحمد','kind':'Customer','balance':0},
    {'id':'m','name':'محمد','kind':'Customer','balance':0},
  ];
  final suppliers=<Json>[{'id':'a','name':'أحمد المورد','kind':'Supplier','balance':0}];
  final products=<Json>[
    {'id':'cheese','name':'جبنة','unit':'كغم','pricingMode':'Weight','salePrice':28},
    {'id':'milk','name':'حليب','unit':'قطعة','pricingMode':'Piece','salePrice':4},
    {'id':'rice','name':'رز','unit':'كيس','pricingMode':'Piece','salePrice':10},
  ];
  VoiceDraft parse(String s,{List<Json>? people,Json? fixedParty,String? fixedKind,bool? fixedSupplier,
      bool modern=true}) => parseVoiceCommand(s,customers:people??customers,
      suppliers:suppliers,products:products,fixedParty:fixedParty,
      fixedKind:fixedKind,fixedSupplier:fixedSupplier,modern:modern);
  group('Palestinian voice commands',(){
    for(final phrase in [
      'يوسف اشترى مني بعشرة شيكل',
      'اشتري مني يوسف ب 10 شيكل',
      'حط على يوسف عشر شيكل',
      'سجل على يوسف ١٠',
      'يوسف أخذ أغراض بعشرة',
      'يوسف اشترى مني عشرة شيكل',
      'يوسف اخد ب١٠ شيكل',
    ]){
      test(phrase,(){
        final d=parse(phrase);
        expect(d.kind,'Debt');expect(d.party?['id'],'y');
        expect(d.totalCents,1000);
      });
    }
    for(final pair in <(String,int)>[
      ('خمستعش',1500),('خمسة وعشرين',2500),('مية وخمسين',15000),
      ('٢٥٫٥',2550),('مية',10000),('خمسين',5000),('ربع',25),
      ('ثلاثة عشر',1300),('ألفين',200000),
    ]){
      test('money ${pair.$1}',()=>expect(parse('سجل على يوسف ${pair.$1} شيكل').totalCents,pair.$2));
    }
    test('weighted and pieces',(){
      final d=parse('يوسف أخذ نص كيلو جبنة وحبتين حليب');
      expect(d.lines.length,2);expect(d.lines[0].quantity,500);
      expect(d.lines[1].quantity,2000);expect(d.totalCents,2200);
    });
    test('sale by amount',(){
      final d=parse('يوسف أخذ جبنة بعشرة شيكل');
      expect(d.lines.single.byAmount,isTrue);
      expect(d.lines.single.quantity,357);
      expect(d.totalCents,1000);
    });
    test('partial payment',(){
      final d=parse('يوسف أخذ أغراض بثلاثين ودفع عشرة');
      expect(d.kind,'Debt');expect(d.totalCents,3000);expect(d.paidCents,1000);
    });
    test('multi-item and partial payment',(){
      final d=parse('يوسف اشترى مني كيلو جبنة بثمانية وعشرين شيكل وكيس رز بعشرة شيكل ودفع خمسة شيكل');
      expect(d.lines.length,2);expect(d.totalCents,3800);expect(d.paidCents,500);
    });
    test('payment',(){
      final d=parse('يوسف دفعلي خمسين شيكل');
      expect(d.kind,'Payment');expect(d.totalCents,5000);expect(d.paidCents,isNull);
    });
    test('bank transfer waiting',(){
      final d=parse('يوسف حوللي خمسين شيكل عالبنك ولسه ما وصل');
      expect(d.kind,'Payment');expect(d.method,'Bank');expect(d.waiting,isTrue);
    });
    test('supplier invoice',(){
      final d=parse('اشتريت من المورد أحمد بضاعة بمية شيكل');
      expect(d.supplier,isTrue);expect(d.kind,'Purchase');expect(d.totalCents,10000);
    });
    test('supplier explicit wholesale item not in catalog',(){
      final d=parse('اشتريت من المورد أحمد كيلو سكر بسعر خمسة');
      expect(d.supplier,isTrue);expect(d.lines.single.price,500);
      expect(d.lines.single.name,'سكر');expect(d.totalCents,500);
    });
    test('supplier must not use retail price',(){
      final d=parse('اشتريت من المورد أحمد كيلو جبنة');
      expect(d.lines,isEmpty);expect(d.warnings,isNotEmpty);
    });
    test('supplier payment',(){
      final d=parse('دفعت للمورد أحمد ميتين');
      expect(d.supplier,isTrue);expect(d.kind,'Payment');expect(d.totalCents,20000);
    });
    test('ambiguous account never chosen',(){
      final d=parse('يوسف اشترى بعشرة',people:[...customers,
        {'id':'other','name':'يوسف محمود','kind':'Customer'}]);
      expect(d.party,isNull);expect(d.warnings,isNotEmpty);
    });
    test('missing quantity never guessed',(){
      final d=parse('يوسف أخذ جبنة ورز');
      expect(d.lines,isEmpty);expect(d.warnings,isNotEmpty);
    });
    test('different quoted price flagged',(){
      final d=parse('يوسف أخذ كيلو جبنة بعشرة');
      expect(d.totalCents,2800);expect(d.warnings,isNotEmpty);
    });
    test('unmatched customer is never auto created',(){
      final d=parse('سجل على سالم خمسين شيكل');
      expect(d.party,isNull);expect(d.warnings,isNotEmpty);
    });
    test('contextual command',(){
      final d=parse('اشترى بعشرين',fixedParty:customers.first,
          fixedKind:'Debt',fixedSupplier:false);
      expect(d.party?['id'],'y');expect(d.totalCents,2000);
    });
    test('legacy backend preserves direct amount',(){
      final d=parse('يوسف اشترى بعشرين شيكل',modern:false);
      expect(d.totalCents,2000);expect(d.lines,isEmpty);
    });
  });
}
