-module(rewrite_logging).
-export([parse_transform/2]).

-define(REWRITE_MODULE, error_logger).
-define(MEMBER_LIST, [info_msg, info_report, error_msg, error_report, warning_msg, warning_report]).


parse_transform(Forms, _Options) ->
    case get_rewrite_function(Forms) of
        {error, no_module_name} -> Forms;
        RewriteFunc -> rewrite_module(Forms, RewriteFunc)
    end.


get_rewrite_function([]) -> {error, no_module_name};
get_rewrite_function([{attribute, _, module, Module}|_]) ->
    ModuleString = atom_to_list(Module),
    fun(FuncName) -> 
        FuncNameString = atom_to_list(FuncName),
        fun(Line, Message) -> 
            string:join([ModuleString, FuncNameString, integer_to_list(Line), " " ++ Message], ":")
        end
    end;
get_rewrite_function([_NotModuleAttribute|Rest]) -> get_rewrite_function(Rest).


rewrite_module(Forms, RewriteFunc) when is_list(Forms)  ->
    lists:map(fun(Node) -> rewrite_module(Node, RewriteFunc) end, Forms);
rewrite_module({'function', Line, Name, Arity, Body}, RewriteFunc) ->
    {function, Line, Name, Arity, find_and_modify(Body, RewriteFunc(Name))};
rewrite_module(Node, _RewriteFunc) ->
    Node.


find_and_modify(Nodes, RewriteFuncInstance) when is_list(Nodes) ->
    lists:map(
        fun(Node) -> find_and_modify(Node, RewriteFuncInstance) end,
        Nodes
    );

find_and_modify({'clause', Line, PS, GS, Body}, RewriteFuncInstance) ->
    {'clause', Line, PS, GS, find_and_modify(Body, RewriteFuncInstance)};

find_and_modify({'call', Line, {'remote',_,{_,_,?REWRITE_MODULE}, {_,_,Func}}=RFun, Args}=Node, RewriteFuncInstance) ->
catch begin
    case lists:member(Func, ?MEMBER_LIST) of
        false -> throw(Node);
        true -> ok
    end,
    NewArgs = case Args of
        [{'string', StringLine, Message}|Tail] ->
            NewMessage = RewriteFuncInstance(Line, Message),
            [{'string', StringLine, NewMessage}|Tail];
        _ -> Args
    end,
    {'call', Line, RFun, NewArgs}
end;
find_and_modify({'call', _, {'remote', _, _, _}, _}=Node, _RewriteFuncInstance) ->
    Node;

find_and_modify({'call', Line, Clauses, Args}, RewriteFuncInstance) ->
    [NClauses, NArgs] = find_and_modify([Clauses, Args], RewriteFuncInstance),
    {'call', Line, NClauses, NArgs};

find_and_modify({'case', Line, CaseClause, ClauseList}, RewriteFuncInstance) ->
    [NCaseClause, NClauseList] = find_and_modify([CaseClause, ClauseList], RewriteFuncInstance),
    {'case', Line, NCaseClause, NClauseList};

find_and_modify({'if', Line, ClauseList}, RewriteFuncInstance) ->
    {'if', Line, find_and_modify(ClauseList, RewriteFuncInstance)};

find_and_modify({'block', Line, ClauseList}, RewriteFuncInstance) ->
    {'block', Line, find_and_modify(ClauseList, RewriteFuncInstance)};

find_and_modify({'fun', Line, {clauses, ClauseList}}, RewriteFuncInstance) ->
    {'fun', Line, {clauses, find_and_modify(ClauseList, RewriteFuncInstance)}};
    
find_and_modify({'fun', Line, Function}, RewriteFuncInstance) ->
    {'fun', Line, find_and_modify(Function, RewriteFuncInstance)};

find_and_modify({'function', _Name, _Arity}=Node, _) ->
    Node;

find_and_modify({'function', _Module, _Name, _Arity}=Node, _) ->
    %FIXME: ?REWRITE_MODULE:MEMBER_FUNCTION/ARITY
    Node;

find_and_modify({'receive', Line, Clauses}, RewriteFuncInstance) ->
    {'receive', Line, find_and_modify(Clauses, RewriteFuncInstance)};

find_and_modify({'receive', Line, R1, R2, R3}, RewriteFuncInstance) ->
    [NR1, NR2, NR3] = find_and_modify([R1, R2, R3], RewriteFuncInstance),
    {'receive', Line, NR1, NR2, NR3};

find_and_modify({'match', Line, L, R}, RewriteFuncInstance) ->
    [NL, NR] = find_and_modify([L, R], RewriteFuncInstance),
    {'match', Line, NL, NR};

find_and_modify({'try', Line, Body, CaseC, CatchC, After}, RewriteFuncInstance)->
    [NBody, NCaseC, NCatchC, NAfter] = find_and_modify(
        [Body, CaseC, CatchC, After],
        RewriteFuncInstance
    ),
    {'try', Line, NBody, NCaseC, NCatchC, NAfter};

find_and_modify({'catch', Line, Exp}, RewriteFuncInstance) ->
    {'catch', Line, find_and_modify(Exp, RewriteFuncInstance)};

find_and_modify({'op', Line, Op, Rep}, RewriteFuncInstance) ->
    {'op', Line, Op, find_and_modify(Rep, RewriteFuncInstance)};

find_and_modify({'op', Line, Op, Rep1, Rep2}, RewriteFuncInstance) ->
    [NewRep1, NewRep2] = find_and_modify([Rep1, Rep2], RewriteFuncInstance),
    {'op', Line, Op, NewRep1, NewRep2};

find_and_modify({'lc', Line, R1, R2}, RewriteFuncInstance) ->
    [NR1, NR2] = find_and_modify([R1, R2], RewriteFuncInstance),
    {'lc', Line, NR1, NR2};

find_and_modify({'generate', Line, R1, R2}, RewriteFuncInstance) ->
    [NR1, NR2] = find_and_modify([R1, R2], RewriteFuncInstance),
    {'generate', Line, NR1, NR2};

find_and_modify({'bc', Line, Rep1, Reps}, RewriteFuncInstance) ->
    [NewRep1, NewReps] = find_and_modify([Rep1, Reps], RewriteFuncInstance),
    {'bc', Line, NewRep1, NewReps};

find_and_modify({'bin', Line, BinElements}, RewriteFuncInstance) ->
    {'bin', Line, find_and_modify(BinElements, RewriteFuncInstance)};

find_and_modify({'bin_element', Line, R1, R2, R3}, RewriteFuncInstance) ->
    [NR1, NR2, NR3] = find_and_modify([R1, R2, R3], RewriteFuncInstance),
    {'bin_element', Line, NR1, NR2, NR3};

find_and_modify({'b_generate', Line, R1, R2}, RewriteFuncInstance) ->
    [NR1, NR2] = find_and_modify([R1, R2], RewriteFuncInstance),
    {'b_generate', Line, NR1, NR2};

find_and_modify({'record', Line, Name, Fields}, RewriteFuncInstance) ->
    {'record', Line, Name, find_and_modify(Fields, RewriteFuncInstance)};

find_and_modify({'record', Line, Name, RecordName, Fields}, RewriteFuncInstance) ->
    {'record', Line, Name, RecordName, find_and_modify(Fields, RewriteFuncInstance)};

find_and_modify({'record_field', Line, R1, Name, R2}, RewriteFuncInstance) ->
    [NR1, NR2] = find_and_modify([R1, R2], RewriteFuncInstance),
    {'record_field', Line, NR1, Name, NR2};

find_and_modify({'record_field', Line, R1, R2}, RewriteFuncInstance) ->
    [NR1, NR2] = find_and_modify([R1, R2], RewriteFuncInstance),
    {'record_field', Line, NR1, NR2};

find_and_modify({'cons', Line, R1, R2}, RewriteFuncInstance) ->
    [NR1, NR2] = find_and_modify([R1, R2], RewriteFuncInstance),
    {'cons', Line, NR1, NR2};

find_and_modify({'tuple', Line, Reps}, RewriteFuncInstance) ->
    {'tuple', Line, find_and_modify(Reps, RewriteFuncInstance)};

find_and_modify(Node, _) ->
    Node.
