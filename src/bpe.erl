-module(bpe).
-author('Maxim Sokhatsky').
-include("bpe.hrl").
-include("api.hrl").
-compile(export_all).

% Instance Management

load(ProcName) -> {ok,Proc} = kvs:get(process,ProcName), Proc.

start(Proc0, Docs) ->
    Proc = case Proc0#process.id of
                undefined -> Id = kvs:next_id("process",1),
                             Proc0#process{id=Id,task=Proc0#process.beginEvent};
                        _ -> Proc0 end,
    kvs:put(Proc),
    Restart = transient,
    Shutdown = 200,
    ChildSpec = { Proc#process.id, 
                  {bpe_proc, start_link, [Proc]},
                  Restart, Shutdown, worker, [bpe_proc] },
    supervisor:start_child(bpe_sup,ChildSpec).

process(ProcId)           -> gen_server:call(ProcId,{get}).
complete(ProcId)          -> gen_server:call(ProcId,{complete}).
complete(Stage,ProcId)    -> gen_server:call(ProcId,{complete,Stage}).
amend(ProcId,Form)        -> gen_server:call(ProcId,{amend,Form}).
noflow_amend(ProcId,Form) -> gen_server:call(ProcId,{noflow_amend,Form}).
event(ProcId,Event)       -> gen_server:call(ProcId,{event,Event}).

complete_while(ProcId) ->
    {complete,Status} = complete(ProcId),
    {complete,Status2} = complete(ProcId),
    case Status == Status2 of
         true -> {complete,Status2};
            _ -> complete_while(ProcId) end.

amend_while(ProcId,Form) ->
    {complete,Status} = amend(ProcId,Form),
    {complete,Status2} = complete(ProcId),
    case Status == Status2 of
         true -> {complete,Status2};
            _ -> complete_while(ProcId) end.

delete_tasks(Proc, Tasks) ->
    Proc#process { tasks = [ Task || Task <- Proc#process.tasks,
                                lists:member(Task#task.name,Tasks) ] }.

history(ProcId) -> kvs:entries(kvs:get(feed,{history,ProcId}),history,undefined).

source(Name, Proc) ->
    case [ Task || Task <- events(Proc), element(#task.name,Task) == Name] of
         [T] -> T;
         [] -> [];
         E -> E end.

task(Name, Proc) -> 
    case [ Task || Task <- tasks(Proc), element(#task.name,Task) == Name] of
         [T] -> T;
         [] -> [];
         E -> E end.

doc(Rec, Proc) ->
    case [ Doc || Doc <- docs(Proc), element(1,Doc) == element(1,Rec)] of
         [D] -> D;
         [] -> [];
         E -> E end.

docs(Proc) -> Proc#process.docs.
tasks(Proc) -> Proc#process.tasks.
events(Proc) -> Proc#process.events.

% Process Schema

new_task(Proc,GivenTask) -> 
   Existed = [ Task || Task<- Proc#process.tasks, Task#task.name == GivenTask#task.name],
   case Existed of
        [] -> Proc#process{tasks=[GivenTask|Proc#process.tasks]};
         _ -> {error,exist,Existed} end.

delete(Proc) -> ok.

val(Document,Proc,Cond) -> val(Document,Proc,Cond,fun(X,Y)-> ok end).
val(Document,Proc,Cond,Action) ->
%    io:format("val: ~p~n",[Document]),
    case Cond(Document,Proc) of
         true -> Action(Document,Proc),
                 {reply,Proc};
            _ -> {reply,Proc#process.task,Proc} end.

