import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/chat_history_db.dart';
import '../../services/legal_ai_service.dart';
import '../article/article_detail_screen.dart';

class LegalAiScreen extends StatefulWidget {
  const LegalAiScreen({super.key});
  @override State<LegalAiScreen> createState()=>_LegalAiScreenState();
}

class _LegalAiScreenState extends State<LegalAiScreen> {
  final c=TextEditingController();
  final scroll=ScrollController();
  final service=LegalAiService.instance;
  final historyDb=ChatHistoryDb.instance;
  final messages=<_Msg>[];
  bool loading=false;
  String? conversationId;

  @override void dispose(){c.dispose();scroll.dispose();super.dispose();}

  Future<void> ask() async {
    if(loading) return;
    final q=c.text.trim();
    if(q.isEmpty)return;
    final previousMessages = messages
        .where((m)=>m.role=='user'||m.role=='assistant')
        .toList();
    final recentMessages = previousMessages.length > 12
        ? previousMessages.skip(previousMessages.length - 12)
        : previousMessages;
    final history=recentMessages
        .map((m)=>{'role':m.role,'content':m.text})
        .toList();

    setState((){messages.add(_Msg.user(q));c.clear();loading=true;});
    _end();
    try{
      final r=await service.ask(question:q,conversationId:conversationId,history:history);
      conversationId ??= r.conversationId;
      if(mounted)setState(()=>messages.add(_Msg.answer(r)));
    }catch(e){
      if(mounted)setState(()=>messages.add(_Msg.error(e.toString())));
    }finally{
      if(mounted){setState(()=>loading=false);_end();}
    }
  }

  Future<void> _showHistory() async {
    if (loading) return;

    try {
      final entries = await historyDb.getHistory(limit: 50);
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          if (entries.isEmpty) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('لا يوجد سجل بحوث حتى الآن.')),
              ),
            );
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * .72,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        entry.query,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.response.isEmpty
                            ? entry.sourceLabel
                            : entry.sourceLabel + ' — ' + entry.response,
                        textAlign: TextAlign.right,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        entry.source == 'local_db'
                            ? Icons.menu_book_rounded
                            : Icons.auto_awesome_rounded,
                        color: context.accent,
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        c.text = entry.query;
                        if (entry.response.isNotEmpty) {
                          setState(() {
                            messages
                              ..clear()
                              ..add(_Msg.user(entry.query))
                              ..add(
                                _Msg.answer(
                                  LegalAiResult(
                                    answer: entry.response,
                                    sources: const [],
                                    conversationId: null,
                                    responseSource: entry.source,
                                  ),
                                ),
                              );
                          });
                          _end();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح سجل البحوث حالياً.')),
      );
    }
  }

  void newChat(){
    if(loading)return;
    setState((){messages.clear();conversationId=null;c.clear();});
  }

  void _end()=>WidgetsBinding.instance.addPostFrameCallback((_){
    if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);
  });

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(
      title:const Text('مساعد موسوعة القوانين'),
      centerTitle:true,
      actions:[
        IconButton(
          tooltip:'سجل البحوث',
          onPressed:loading?null:_showHistory,
          icon:const Icon(Icons.history_rounded),
        ),
        IconButton(
          tooltip:'محادثة جديدة',
          onPressed:loading?null:newChat,
          icon:const Icon(Icons.add_comment_rounded),
        ),
      ],
    ),
    body:SafeArea(child:Column(children:[
      if(messages.isEmpty)_Intro(),
      Expanded(child:messages.isEmpty
        ?_Empty(onTap:(q){c.text=q;ask();})
        :ListView.builder(controller:scroll,padding:const EdgeInsets.all(14),itemCount:messages.length,itemBuilder:(_,i)=>_Message(m:messages[i]))),
      if(loading)
        Padding(
          padding:const EdgeInsets.symmetric(horizontal:14,vertical:5),
          child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[
            Text('جاري البحث في القوانين...',style:TextStyle(color:context.textSecondary,fontSize:12)),
            const SizedBox(width:8),
            SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:context.accent)),
          ]),
        ),
      Container(
        padding:const EdgeInsets.fromLTRB(8,6,8,10),
        decoration:BoxDecoration(color:context.surfaceAlt,border:Border(top:BorderSide(color:context.divider))),
        child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          IconButton(onPressed:loading?null:ask,icon:Icon(Icons.send_rounded,color:context.accent)),
          Expanded(child:TextField(
            controller:c,enabled:!loading,minLines:1,maxLines:5,textAlign:TextAlign.right,
            decoration:const InputDecoration(hintText:'اكتب سؤالك القانوني هنا...',border:InputBorder.none),
            onSubmitted:(_)=>ask(),
          )),
        ]),
      )
    ])),
  );
}

class _Intro extends StatelessWidget{
  @override Widget build(BuildContext context)=>Container(
    margin:const EdgeInsets.fromLTRB(14,14,14,8),padding:const EdgeInsets.all(16),
    decoration:BoxDecoration(color:context.surfaceAlt,borderRadius:BorderRadius.circular(22),border:Border.all(color:context.accent.withOpacity(.35))),
    child:Row(children:[
      Icon(Icons.balance_rounded,color:context.accent,size:38),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Text('مساعد موسوعة القوانين اليمنية',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18,color:context.textPrimary)),
        const SizedBox(height:4),
        Text('اسأل عن نص قانوني أو مادة محددة، وسأبحث في المواد المتاحة في الموسوعة وأعرض مصادر الإجابة.',textAlign:TextAlign.right,style:TextStyle(color:context.textSecondary,height:1.45)),
        const SizedBox(height:7),
        Text('للمعلومات العامة وليس بديلاً عن مراجعة النص الرسمي أو المختص القانوني.',textAlign:TextAlign.right,style:TextStyle(fontSize:11,color:context.textSecondary,height:1.4)),
      ]))
    ]));
}

class _Empty extends StatelessWidget{
  final ValueChanged<String> onTap; const _Empty({required this.onTap});
  @override Widget build(BuildContext context){
    const qs=['ما هي شروط الطلاق؟','ما عقوبة السرقة؟','ما المادة المتعلقة بالنفقة؟','اشرح لي المادة 15 بطريقة بسيطة.','ما الفرق بين النصين القانونيين؟'];
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,16),children:[
      Text('أسئلة مقترحة',textAlign:TextAlign.right,style:TextStyle(fontWeight:FontWeight.w800,color:context.textPrimary)),
      const SizedBox(height:10),
      for(final q in qs)Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
        leading:Icon(Icons.arrow_back_ios_new_rounded,size:15,color:context.accent),
        title:Text(q,textAlign:TextAlign.right),onTap:()=>onTap(q),
      )),
    ]);
  }
}

class _Msg{
  final String role,text; final LegalAiResult? result;
  const _Msg(this.role,this.text,this.result);
  factory _Msg.user(String t)=>_Msg('user',t,null);
  factory _Msg.answer(LegalAiResult r)=>_Msg('assistant',r.answer,r);
  factory _Msg.error(String t)=>_Msg('error',t,null);
}

class _Message extends StatelessWidget{
  final _Msg m; const _Message({required this.m});
  @override Widget build(BuildContext context){
    final user=m.role=='user',err=m.role=='error';
    return Align(
      alignment:user?Alignment.centerLeft:Alignment.centerRight,
      child:Container(
        constraints:const BoxConstraints(maxWidth:760),margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(14),
        decoration:BoxDecoration(
          color:user?context.accent.withOpacity(.12):err?Colors.red.withOpacity(.08):context.surfaceAlt,
          borderRadius:BorderRadius.circular(18),
          border:Border.all(color:err?Colors.red.withOpacity(.25):context.divider),
        ),
        child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Row(mainAxisSize:MainAxisSize.min,children:[
            if(!user&&!err)Icon(Icons.balance_rounded,size:16,color:context.accent),
            if(!user&&!err)const SizedBox(width:5),
            Text(user?'سؤالك':err?'تنبيه':'المساعد',style:TextStyle(fontWeight:FontWeight.w900,color:err?Colors.redAccent:context.accent)),
          ]),
          const SizedBox(height:7),
          SelectableText(m.text,textAlign:TextAlign.right,style:TextStyle(color:context.textPrimary,height:1.7)),
          if(m.result!=null)...[
            const SizedBox(height:12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                m.result!.responseSource == 'local_db'
                    ? 'المصدر: نصوص الموسوعة + تحليل الذكاء الاصطناعي'
                    : 'المصدر: بحث الويب عبر الذكاء الاصطناعي (احتياطي)',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ),
            if(m.result!.sources.isNotEmpty)...[
              const SizedBox(height:16),
              Text('المواد القانونية المستخدمة',textAlign:TextAlign.right,style:TextStyle(fontWeight:FontWeight.w900,color:context.textPrimary)),
              const SizedBox(height:8),
              for(final s in m.result!.sources)_Source(s:s),
            ],
          ]
        ]),
      ),
    );
  }
}

class _Source extends StatelessWidget{
  final LegalAiSource s; const _Source({required this.s});
  @override Widget build(BuildContext context)=>Card(
    child:InkWell(
      onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>ArticleDetailScreen(maddaId:s.articleId))),
      child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Text(s.lawName,textAlign:TextAlign.right,style:TextStyle(fontWeight:FontWeight.w800,color:context.accent)),
        if(s.reference != null && s.reference!.trim().isNotEmpty) ...[
          const SizedBox(height:4),
          Text(s.reference!,textAlign:TextAlign.right,style:TextStyle(color:context.textSecondary,fontSize:11)),
        ],
        const SizedBox(height:4),
        Text('المادة: ${s.articleNumber}',textAlign:TextAlign.right,style:TextStyle(fontWeight:FontWeight.w700,color:context.textPrimary)),
        const SizedBox(height:7),
        Text(s.articleText,maxLines:5,overflow:TextOverflow.ellipsis,textAlign:TextAlign.right,style:TextStyle(color:context.textSecondary,height:1.5)),
        const SizedBox(height:8),
        Row(mainAxisAlignment:MainAxisAlignment.start,children:[
          Text('فتح المادة في الموسوعة',style:TextStyle(color:context.accent,fontWeight:FontWeight.w700)),
          const SizedBox(width:5),Icon(Icons.open_in_new_rounded,size:16,color:context.accent),
        ])
      ]))
    )
  );
}
