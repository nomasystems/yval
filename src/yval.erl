%%%-------------------------------------------------------------------
%%% @author Evgeny Khramtsov <ekhramtsov@process-one.net>
%%% @copyright (C) 2002-2020 ProcessOne, SARL. All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%%-------------------------------------------------------------------
-module(yval).

%% Include files
-include_lib("kernel/include/logger.hrl").

%% API
-export([validate/2, fail/2]).
-export([format_error/1, format_error/2, format_ctx/1]).
%% Simple types
-export([pos_int/0, pos_int/1, non_neg_int/0, non_neg_int/1]).
-export([int/0, int/2, number/1, number/2, pos_number/0, octal/0]).
-export([binary/0, binary/1, binary/2]).
-export([string/0, string/1, string/2]).
-export([enum/1, bool/0, atom/0, any/0]).
%% Complex types
-export([url/0, url/1]).
-export([file/0, file/1]).
-export([directory/0, directory/1]).
-export([ip/0, ipv4/0, ipv6/0, ip_mask/0, port/0]).
-export([re/0, re/1, glob/0, glob/1]).
-export([path/0, binary_sep/1]).
-export([beam/0, beam/1, base64/0]).
-export([hex/0]).
-export([timeout/1, timeout/2]).
-export([rfc3339_time/1]).
-export([term/0, percent/0, percent/2]).
%% Composite types
-export([list/1, list/2]).
-export([list_or_single/1, list_or_single/2]).
-export([map/2, map/3]).
-export([either/2, and_then/2, non_empty/1]).
-export([options/1, options/2]).

-define(is_validator(Term), is_function(Term, 1)).

-type infinity() :: infinity | infinite | unlimited.
-type timeout_unit() :: millisecond | second | minute | hour | day.
-type time_unit() :: microsecond | millisecond | nanosecond | second.
-type exports() :: [{atom(), arity()} | [{atom(), arity()}]].
-type options() :: [{atom(), term()}] |
                   #{atom() => term()} |
                   dict:dict(atom(), term()).
-type return_type() :: list | map | dict | orddict.
-type unique_opt() :: unique | {unique, boolean()}.
-type sorted_opt() :: sorted | {sorted, boolean()}.
-type ctx() :: [atom() | binary() | integer()].
-type yaml_val() :: atom() | number() | binary().
-type yaml_list() :: [yaml()].
-type yaml_map() :: [{yaml_val(), yaml()}].
-type yaml() :: yaml_val() | yaml_list() | yaml_map().
-type validator_option() :: {required, [atom()]} |
                            {defaults, #{atom() => term()}} |
                            {disallowed, [atom()]} |
                            unique | {unique, boolean()} |
                            {return, return_type()}.
-type validator() :: fun((yaml()) -> term()).
-type validator(T) :: fun((yaml()) -> T).
-type validators() :: #{atom() => validator()}.
-type error_reason() :: term().
-type error_return() :: {error, error_reason(), ctx()}.

-export_type([validator/0, validator/1, validators/0, validator_option/0]).
-export_type([error_return/0, error_reason/0, ctx/0]).

%%%===================================================================
%%% API
%%%===================================================================
-spec validate(validator(), yaml()) -> {ok, any()} | error_return().
validate(Validator, Y) ->
    try {ok, Validator(Y)}
    catch _:{?MODULE, Why, Ctx} ->
            {error, Why, Ctx};
          Class:Reason:Stacktrace ->
            _ = erase_ctx(),
            erlang:raise(Class, Reason, Stacktrace)
    end.

-spec fail(module(), term()) -> no_return().
fail(Mod, Reason) ->
    fail({Mod, Reason}).

%%%===================================================================
%%% Validators
%%%===================================================================
-spec enum([atom() | binary()]) -> validator(atom() | binary()).
enum([H|_] = List) when is_atom(H); is_binary(H) ->
    fun(Val) ->
            Member = if is_binary(H) -> to_binary(Val);
                        is_atom(H) -> to_existing_atom(Val)
                     end,
            case lists:member(Member, List) of
                true -> Member;
                false -> fail({bad_enum, List, Member})
            end
    end.

-spec bool() -> validator(boolean()).
bool() ->
    fun(Val) ->
            case to_existing_atom(Val) of
                on -> true;
                off -> false;
                yes -> true;
                no -> false;
                y -> true;
                n -> false;
                true -> true;
                false -> false;
                Bad -> fail({bad_bool, Bad})
            end
    end.

-spec pos_int() -> validator(pos_integer()).
pos_int() ->
    fun(Val) ->
            case to_int(Val) of
                I when I>0 -> I;
                Bad -> fail({bad_pos_int, Bad})
            end
    end.

-spec pos_int(infinity()) -> validator(pos_integer() | infinity()).
pos_int(Inf) when Inf == infinity; Inf == infinite; Inf == unlimited ->
    fun(Val) ->
            case to_int(Val, Inf) of
                I when I>0 -> I;
                Bad -> fail({bad_pos_int, Inf, Bad})
            end
    end.

-spec non_neg_int() -> validator(non_neg_integer()).
non_neg_int() ->
    fun(Val) ->
            case to_int(Val) of
                I when I>=0 -> I;
                Bad -> fail({bad_non_neg_int, Bad})
            end
    end.

-spec non_neg_int(infinity()) -> validator(non_neg_integer() | infinity()).
non_neg_int(Inf) when Inf == infinity; Inf == infinite; Inf == unlimited ->
    fun(Val) ->
            case to_int(Val, Inf) of
                I when I>=0 -> I;
                Bad -> fail({bad_non_neg_int, Inf, Bad})
            end
    end.

-spec int() -> validator(integer()).
int() ->
    fun to_int/1.

-spec int(integer(), integer() | infinity) -> validator(integer()).
int(Min, Max) when is_integer(Min) andalso
                   (is_integer(Max) orelse Max == infinity) andalso
                   Min =< Max ->
    fun(Val) ->
            case to_int(Val) of
                I when I>=Min, I=<Max -> I;
                Bad -> fail({bad_int, Min, Max, Bad})
            end
    end.

-spec number(number()) -> validator(number()).
number(Min) ->
    number(Min, infinity).

-spec number(number(), number() | infinity) -> validator(number()).
number(Min, Max) when is_number(Min) andalso
                      (is_number(Max) orelse Max == infinity) andalso
                      Min =< Max ->
    fun(Val) ->
            case to_number(Val) of
                N when N >= Min, N =< Max -> N;
                Bad -> fail({bad_number, Min, Max, Bad})
            end
    end.

-spec pos_number() -> validator(number()).
pos_number() ->
    fun(Val) ->
            case to_number(Val) of
                N when N>0 -> N;
                Bad -> fail({bad_pos_number, Bad})
            end
    end.

-spec percent() -> validator(number()).
percent() ->
    percent(0.0, 1.0).

-spec percent(number(), number() | infinity) -> validator(number()).
percent(Min, Max) ->
    fun(Val) when is_number(Val) ->
            (number(Min, Max))(Val);
       (Val) ->
            case string:trim(to_string(Val)) of
                "" -> fail(empty_string);
                S ->
                    case lists:reverse(S) of
                        [$%|T] ->
                            Num = string_to_number(string:trim(lists:reverse(T)))/100,
                            (number(Min, Max))(Num);
                        _ ->
                            fail({bad_number, list_to_binary(S)})
                    end
            end
    end.

-spec binary() -> validator(binary()).
binary() ->
    fun to_binary/1.

-spec binary(iodata()) -> validator(binary()).
binary(Regexp) ->
    binary(Regexp, [unicode]).

-spec binary(iodata(), [proplists:property()]) -> validator(binary()).
binary(Regexp, Opts) when is_list(Regexp) orelse is_binary(Regexp) ->
    {ok, Re} = re:compile(Regexp, Opts),
    fun(Val) ->
            Bin = to_binary(Val),
            case re:run(Bin, Re) of
                {match, _} -> Bin;
                nomatch ->
                    case lists:member(unicode, Opts) of
                        true ->
                            case is_unicode(Bin, utf8) of
                                true -> fail({nomatch, Regexp, Bin});
                                false -> fail({bad_unicode, Bin})
                            end;
                        false ->
                            fail({nomatch, Regexp, Bin})
                    end
            end
    end.

-spec atom() -> validator(atom()).
atom() ->
    fun to_atom/1.

-spec string() -> validator(string()).
string() ->
    fun to_string/1.

-spec string(iodata()) -> validator(string()).
string(Regexp) ->
    string(Regexp, [unicode]).

-spec string(iodata(), [proplists:property()]) -> validator(string()).
string(Regexp, Opts) when is_list(Regexp) orelse is_binary(Regexp) ->
    and_then(
      binary(Regexp, Opts),
      fun binary_to_list/1).

-spec term() -> validator(term()).
term() ->
    fun(Val) ->
            case string:trim(to_string(Val)) of
                "" -> fail(empty_string);
                Str1 ->
                    Str2 = case lists:last(Str1) of
                               $. -> Str1;
                               _ -> Str1 ++ "."
                           end,
                    case erl_scan:string(Str2) of
                        {ok, Tokens, _} ->
                            case erl_parse:parse_term(Tokens) of
                                {ok, Term} -> Term;
                                {error, Reason} -> fail({bad_term, Reason})
                            end;
                        {error, Reason, _} ->
                            fail({bad_term, Reason})
                    end
            end
    end.

-spec binary_sep(iodata()) -> validator([binary()]).
binary_sep(Sep) ->
    fun(Val) ->
            Bin = to_binary(Val),
            lists:filtermap(
              fun(<<>>) -> false;
                 (S) -> {true, S}
              end, re:split(Bin, Sep))
    end.

-spec path() -> validator(binary()).
path() ->
    fun prep_path/1.

-spec file() -> validator(binary()).
file() ->
    file(read).

-spec file(read | write) -> validator(binary()).
file(read) ->
    fun(Val) ->
            Path = prep_path(Val),
            case file:open(Path, [read]) of
                {ok, Fd} ->
                    _ = file:close(Fd),
                    Path;
                {error, Why} ->
                    fail({read_file, Why, Path})
            end
    end;
file(write) ->
    fun(Val) ->
            Path = prep_path(Val),
            case filelib:ensure_dir(Path) of
                ok ->
                    case file:open(Path, [append]) of
                        {ok, Fd} ->
                            _ = file:close(Fd),
                            Path;
                        {error, Why} ->
                            fail({create_file, Why, Path})
                    end;
                {error, Why} ->
                    fail({create_dir, Why, filename:dirname(Path)})
            end
    end.

-spec directory() -> validator(binary()).
directory() ->
    directory(read).

-spec directory(read | write) -> validator(binary()).
directory(read) ->
    fun(Val) ->
            Path = prep_path(Val),
            case filelib:is_dir(Path) of
                true ->
                    Path;
                false ->
                    case file:list_dir(Path) of
                        {error, Why} ->
                            fail({read_dir, Why, Path});
                        {ok, _} ->
                            Path
                    end
            end
    end;
directory(write) ->
    fun(Val) ->
            Path = prep_path(Val),
            case filelib:ensure_dir(filename:join(Path, "foo")) of
                ok ->
                    Path;
                {error, Why} ->
                    fail({create_dir, Why, Path})
            end
    end.

-spec url() -> validator(binary()).
url() ->
    url([http, https]).

-spec url([atom()]) -> validator(binary()).
url(Schemes0) ->
    Schemes = [atom_to_binary(S, latin1) || S <- Schemes0],
    fun(Val) ->
            URL = to_binary(Val),
            case uri_string:parse(URL) of
                #{port := Port} when Port < 1;
                                     Port > 65535 ->
                    fail({bad_url, bad_port, URL});
                #{} = Parsed ->
                    case {maps:get(scheme, Parsed, <<>>),
                          maps:get(host, Parsed, <<>>)} of
                        {<<>>, _} ->
                            fail({bad_url, no_scheme, URL});
                        {_, <<>>} ->
                            fail({bad_url, empty_host, URL});
                        {Scheme, _} when Schemes /= [] ->
                            case lists:member(Scheme, Schemes) of
                                true ->
                                    URL;
                                false ->
                                    fail({bad_url, {unsupported_scheme, Scheme},
                                          URL})
                            end;
                        {_, _} ->
                            URL
                    end;
                {error, Why, _Info} ->
                    fail({bad_url, Why, URL})
            end
    end.

-spec octal() -> validator(non_neg_integer()).
octal() ->
    fun(Val) ->
            Bin = to_binary(Val),
            try binary_to_integer(Bin, 8)
            catch _:_ -> fail({bad_octal, Bin})
            end
    end.

-spec ipv4() -> validator(inet:ip4_address()).
ipv4() ->
    fun(Val) ->
            S = to_string(Val),
            case inet:parse_ipv4_address(to_string(Val)) of
                {ok, IP} -> IP;
                _ -> fail({bad_ipv4, S})
            end
    end.

-spec ipv6() -> validator(inet:ip6_address()).
ipv6() ->
    fun(Val) ->
            S = to_string(Val),
            case inet:parse_ipv6strict_address(S) of
                {ok, IP} -> IP;
                _ -> fail({bad_ipv6, S})
            end
    end.

-spec ip() -> validator(inet:ip_address()).
ip() ->
    fun(Val) ->
            S = to_string(Val),
            case inet:parse_address(S) of
                {ok, IP} -> IP;
                _ -> fail({bad_ip, S})
            end
    end.

-spec ip_mask() -> validator(
                     {inet:ip4_address(), 0..32} |
                     {inet:ip6_address(), 0..128}).
ip_mask() ->
    fun(Val) ->
            S = to_string(Val),
            case parse_ip_netmask(S) of
                {ok, IP, Mask} -> {IP, Mask};
                _ -> fail({bad_ip_mask, S})
            end
    end.

-spec port() -> validator(1..65535).
port() ->
    int(1, 65535).

-spec timeout(timeout_unit()) -> validator(pos_integer()).
timeout(Unit) ->
    fun(Val) ->
            to_timeout(Val, Unit)
    end.

-spec timeout(timeout_unit(), infinity()) -> validator(pos_integer() | infinity()).
timeout(Unit, Inf) ->
    fun(Val) ->
            to_timeout(Val, Unit, Inf)
    end.

-spec rfc3339_time(time_unit()) -> validator(non_neg_integer()).
rfc3339_time(Unit) ->
    fun(Val) ->
            S = to_string(Val),
            try calendar:rfc3339_to_system_time(S, [{unit, Unit}]) of
                Int -> Int
            catch _:_ ->
                    fail({bad_rfc3339_time, S})
            end
    end.

-spec re() -> validator().
re() ->
    re([unicode]).

-spec re([proplists:property()]) -> validator().
re(Opts) ->
    fun(Val) ->
            Bin = to_binary(Val),
            case re:compile(Bin, Opts) of
                {ok, RE} -> RE;
                {error, Why} -> fail({bad_regexp, Why, Bin})
            end
    end.

-spec glob() -> validator().
glob() ->
    glob([]).

-spec glob([proplists:property()]) -> validator().
glob(Opts) ->
    fun(Val) ->
            S = to_string(Val),
            case re:compile(sh_to_awk(S), Opts) of
                {ok, RE} -> RE;
                {error, Why} -> fail({bad_glob, Why, S})
            end
    end.

-spec beam() -> validator(module()).
beam() ->
    beam([]).

-spec beam(exports()) -> validator(module()).
beam(Exports) ->
    fun(Val) ->
            Mod = to_atom(Val),
            case code:ensure_loaded(Mod) of
                {module, Mod} ->
                    lists:foreach(
                      fun([]) ->
                              ok;
                         (L) when is_list(L) ->
                              case lists:any(
                                     fun({F, A}) ->
                                             erlang:function_exported(Mod, F, A)
                                     end, L) of
                                  true -> ok;
                                  false -> fail({bad_export, hd(L), Mod})
                              end;
                         ({F, A}) ->
                              case erlang:function_exported(Mod, F, A) of
                                  true -> ok;
                                  false -> fail({bad_export, {F, A}, Mod})
                              end
                      end, Exports),
                    Mod;
                _ ->
                    fail({bad_module, Mod})
            end
    end.

-spec base64() -> validator(binary()).
base64() ->
    fun(Val) ->
            B = to_binary(Val),
            try base64:decode(B)
            catch _:_ -> fail({bad_base64, B})
            end
    end.

-spec hex() -> validator(binary()).
hex() ->
    fun(Val) ->
            B = to_binary(Val),
            try from_hex(B)
            catch _:_ -> fail({bad_hex, B})
            end
    end.

-spec non_empty(validator(T)) -> validator(T).
non_empty(Fun) ->
    fun(Val) ->
            case Fun(Val) of
                '' -> fail(empty_atom);
                <<"">> -> fail(empty_binary);
                [] -> fail(empty_list);
                Ret -> Ret
            end
    end.

-spec list(validator(T)) -> validator([T]).
list(Fun) ->
    list(Fun, []).

-spec list(validator(T), [unique_opt() | sorted_opt()]) -> validator([T]).
list(Fun, Opts) when ?is_validator(Fun) ->
    fun(L) when is_list(L) ->
            {L1, _} = lists:mapfoldl(
                        fun(Val, Pos) ->
                                Ctx = get_ctx(),
                                put_ctx([Pos|Ctx]),
                                Val1 = Fun(Val),
                                put_ctx(Ctx),
                                {Val1, Pos+1}
                        end, 1, L),
            L2 = unique(L1, Opts),
            case proplists:get_bool(sorted, Opts) of
                true -> lists:sort(L2);
                false -> L2
            end;
       (Bad) ->
            fail({bad_list, Bad})
    end.

-spec list_or_single(validator(T)) -> validator([T]).
list_or_single(Fun) ->
    list_or_single(Fun, []).

-spec list_or_single(validator(T), [unique_opt() | sorted_opt()]) -> validator([T]).
list_or_single(Fun, Opts) when ?is_validator(Fun) ->
    fun(L) when is_list(L) ->
            (list(Fun, Opts))(L);
       (V) ->
            [Fun(V)]
    end.

-spec map(validator(T1), validator(T2)) -> validator([{T1, T2}] | #{T1 => T2}).
map(Fun1, Fun2) ->
    map(Fun1, Fun2, [{return, list}]).

-spec map(validator(T1), validator(T2),
          [{return, return_type()} | unique_opt()]) ->
                 validator([{T1, T2}] | #{T1 => T2} | dict:dict(T1, T2)).
map(Fun1, Fun2, Opts) when ?is_validator(Fun1) andalso
                           ?is_validator(Fun2) ->
    fun(L) when is_list(L) ->
            M1 = lists:map(
                   fun({Key, Val}) ->
                           Key1 = Fun1(Key),
                           Ctx = get_ctx(),
                           put_ctx([Key|Ctx]),
                           Val1 = Fun2(Val),
                           put_ctx(Ctx),
                           {Key1, Val1};
                      (_) ->
                           fail({bad_map, L})
                   end, L),
            M2 = unique(M1, Opts),
            case proplists:get_value(return, Opts, list) of
                list -> M2;
                map -> maps:from_list(M2);
                orddict -> orddict:from_list(M2);
                dict -> dict:from_list(M2)
            end;
       (Bad) ->
            fail({bad_map, Bad})
    end.

-spec either(atom(), validator(T)) -> validator(atom() | T);
            (validator(T1), validator(T2)) -> validator(T1 | T2).
either(Atom, Fun) when is_atom(Atom) andalso ?is_validator(Fun) ->
    either(enum([Atom]), Fun);
either(Fun1, Fun2) when ?is_validator(Fun1) andalso
                        ?is_validator(Fun2) ->
    fun(Val) ->
            Ctx = get_ctx(),
            try Fun1(Val)
            catch _:_ ->
                    put_ctx(Ctx),
                    Fun2(Val)
            end
    end.

-spec and_then(validator(T1), fun((T1) -> T2)) -> validator(T2).
and_then(Fun, Then) when ?is_validator(Fun) andalso
                         is_function(Then, 1) ->
    fun(Val) -> Then(Fun(Val)) end.

-spec any() -> validator(yaml()).
any() ->
    fun(Val) -> Val end.

-spec options(validators()) -> validator().
options(Validators) ->
    options(Validators, [unique]).

-spec options(validators(), [validator_option()]) -> validator().
options(Validators, Options) ->
    fun(Opts) when is_list(Opts) ->
            Required = proplists:get_value(required, Options, []),
            Defaults = proplists:get_value(defaults, Options, #{}),
            Disallowed = proplists:get_value(disallowed, Options, []),
            CheckDups = proplists:get_bool(unique, Options),
            Return = proplists:get_value(return, Options, list),
            DefaultValidator = maps:get('_', Validators, undefined),
            validate_options(Opts, Validators, DefaultValidator,
                             Required, Defaults, Disallowed, CheckDups, Return);
       (Bad) ->
            fail({bad_map, Bad})
    end.

%%%===================================================================
%%% Formatters
%%%===================================================================
-spec format_error(error_reason(), ctx()) -> string().
format_error(Why, []) ->
    format_error(Why);
format_error(Why, Ctx) ->
    format_ctx(Ctx) ++ ": " ++ format_error(Why).

-spec format_error(error_reason()) -> string().
format_error({bad_atom, Bad}) ->
    format("Expected string, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_binary, Bad}) ->
    format("Expected string, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_unicode, _}) ->
    "Non UTF-8 string";
format_error({bad_bool, Bad}) ->
    format("Expected boolean, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_base64, _}) ->
    format("Invalid Base64 string", []);
format_error({bad_hex, _}) ->
    format("Invalid hexadecimal string", []);
format_error({bad_cwd, Why}) ->
    format("Failed to get current directory name: ~s",
           [file:format_error(Why)]);
format_error({bad_enum, _Known, Bad}) ->
    format("Unexpected value: ~s", [Bad]);
format_error({bad_export, {F, A}, Mod}) ->
    format("Module '~s' doesn't export function ~s/~B", [Mod, F, A]);
format_error({bad_glob, {Reason, _}, _}) ->
    format("Invalid glob expression: ~s", [Reason]);
format_error({bad_int, Bad}) ->
    format("Expected integer, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_int, Min, infinity, Bad}) ->
    format("Expected integer >= ~B, got: ~B", [Min, Bad]);
format_error({bad_int, Min, Max, Bad}) ->
    format("Expected integer from ~B to ~B, got: ~B", [Min, Max, Bad]);
format_error({bad_ip_mask, S}) ->
    format("Invalid IP address or network mask: ~s", [S]);
format_error({bad_ip, S}) ->
    format("Invalid IP address: ~s", [S]);
format_error({bad_ipv4, S}) ->
    format("Invalid IPv4 address: ~s", [S]);
format_error({bad_ipv6, S}) ->
    format("Invalid IPv6 address: ~s", [S]);
format_error({bad_length, Limit}) ->
    format("The value must not exceed ~B octets in length", [Limit]);
format_error({bad_list, Bad}) ->
    format("Expected list, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_map, Bad}) ->
    format("Expected map, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_module, Mod}) ->
    format("Unknown module: ~s", [Mod]);
format_error({bad_non_neg_int, Bad}) ->
    format("Expected non negative integer, got: ~B", [Bad]);
format_error({bad_non_neg_int, Inf, Bad}) ->
    format("Expected non negative integer or '~s', got: ~B", [Inf, Bad]);
format_error({bad_number, Bad}) ->
    format("Expected number, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_number, Min, infinity, Bad}) ->
    format("Expected number >= ~p, got: ~p", [Min, Bad]);
format_error({bad_number, Min, Max, Bad}) ->
    format("Expected number from ~p to ~p, got: ~p", [Min, Max, Bad]);
format_error({bad_pos_number, Bad}) ->
    format("Expected positive number, got: ~p", [Bad]);
format_error({bad_octal, Bad}) ->
    format("Expected octal, got: ~s", [Bad]);
format_error({bad_pos_int, Bad}) ->
    format("Expected positive integer, got: ~B", [Bad]);
format_error({bad_pos_int, Inf, Bad}) ->
    format("Expected positive integer or '~s', got: ~B", [Inf, Bad]);
format_error({bad_regexp, {Reason, _}, _}) ->
    format("Invalid regular expression: ~s", [Reason]);
format_error({bad_timeout, Bad}) ->
    format("Expected positive integer, got ~s instead", [format_yaml_type(Bad)]);
format_error({bad_timeout, Inf, Bad}) ->
    format("Expected positive integer or '~s', got ~s instead",
           [Inf, format_yaml_type(Bad)]);
format_error({bad_timeout_unit, Bad}) ->
    format("Unexpected timeout unit: ~s", [Bad]);
format_error({bad_timeout_min, Unit}) ->
    format("Timeout must not be shorter than one ~s", [Unit]);
format_error({bad_rfc3339_time, S}) ->
    format("Expected RFC 3339 timestamp, got: ~s", [S]);
format_error({bad_url, empty_host, URL}) ->
    format("Empty hostname in the URL: ~s", [URL]);
format_error({bad_url, no_scheme, URL}) ->
    format("No scheme in the URL: ~s", [URL]);
format_error({bad_url, {unsupported_scheme, Scheme}, URL}) ->
    format("Unsupported scheme '~s' in the URL: ~s", [Scheme, URL]);
format_error({bad_url, bad_port, URL}) ->
    format("Invalid port number in the URL: ~s", [URL]);
format_error({bad_url, _, URL}) ->
    format("Invalid URL: ~s", [URL]);
format_error({bad_term, {LineNo, Module, Reason}}) ->
    format("Invalid Erlang term: at line ~B: ~s", [LineNo, Module:format_error(Reason)]);
format_error({create_dir, Why, Path}) ->
    format("Failed to create directory '~s': ~s",
           [Path, file:format_error(Why)]);
format_error({create_file, Why, Path}) ->
    format("Failed to open file '~s' for writing: ~s",
           [Path, file:format_error(Why)]);
format_error({disallowed_option, Opt}) ->
    format("Parameter '~s' is not allowed in this context", [Opt]);
format_error({duplicated_key, Key}) ->
    format("Duplicated key: ~s", [format_yaml(Key)]);
format_error({duplicated_value, Val}) ->
    format("Duplicated value: ~s", [format_yaml(Val)]);
format_error({duplicated_option, Opt}) ->
    format("Duplicated parameter: ~s", [Opt]);
format_error(empty_atom) ->
    format("Empty string is not allowed", []);
format_error(empty_binary) ->
    format("Empty string is not allowed", []);
format_error(empty_list) ->
    format("Empty list is not allowed", []);
format_error(empty_string) ->
    format("Empty string is not allowed", []);
format_error({missing_option, Opt}) ->
    format("Missing required parameter: ~s", [Opt]);
format_error({nomatch, Regexp, Data}) ->
    format("String '~s' doesn't match regular expression: ~s",
           [Data, Regexp]);
format_error({read_dir, Why, Path}) ->
    format("Failed to read directory '~s': ~s",
           [Path, file:format_error(Why)]);
format_error({read_file, Why, Path}) ->
    format("Failed to read file '~s': ~s",
           [Path, file:format_error(Why)]);
format_error({unknown_option, _Known, Opt}) ->
    format("Unknown parameter: ~s", [Opt]);
format_error({Mod, Reason}) when is_atom(Mod) ->
    Mod:format_error(Reason);
format_error(Unexpected) ->
    format("Unexpected error reason: ~p", [Unexpected]).

-spec format_ctx(ctx()) -> string().
format_ctx([]) ->
    "Validation error";
format_ctx([_|_] = Ctx) ->
    format("Invalid value of parameter '~s'",
           [string:join(
              lists:map(
                fun(A) when is_atom(A) ->
                        atom_to_list(A);
                   (B) when is_binary(B) ->
                        "'" ++ binary_to_list(B) ++ "'";
                   (I) when is_integer(I) ->
                        integer_to_list(I);
                   (Unexpected) ->
                        lists:flatten(io_lib:format("~p", [Unexpected]))
                end, Ctx),
              "->")]).

-spec format(iodata(), list()) -> string().
format(Fmt, Args) ->
    lists:flatten(io_lib:format(Fmt, Args)).

-spec format_yaml_type(yaml()) -> string().
format_yaml_type(<<>>) ->
    "empty string";
format_yaml_type('') ->
    "empty string";
format_yaml_type([]) ->
    "empty list";
format_yaml_type(I) when is_integer(I) ->
    "integer";
format_yaml_type(N) when is_number(N) ->
    "number";
format_yaml_type(B) when is_binary(B) ->
    "string";
format_yaml_type(A) when is_atom(A) ->
    "string";
format_yaml_type([{_, _}|_]) ->
    "map";
format_yaml_type([_|_]) ->
    "list";
format_yaml_type(Unexpected) ->
    lists:flatten(io_lib:format("~p", [Unexpected])).

-spec format_yaml(yaml()) -> iodata().
format_yaml(I) when is_integer(I) ->
    integer_to_list(I);
format_yaml(B) when is_atom(B) ->
    try erlang:atom_to_binary(B, latin1)
    catch _:badarg -> erlang:atom_to_binary(B, utf8)
    end;
format_yaml(Y) ->
    S = try iolist_to_binary(Y)
        catch _:_ -> list_to_binary(io_lib:format("~p", [Y]))
        end,
    case binary:match(S, <<"\n">>) of
        nomatch -> S;
        _ -> [io_lib:nl(), S]
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%%===================================================================
%%% Auxiliary functions
%%%===================================================================
-spec to_binary(term()) -> binary().
to_binary(A) when is_atom(A) ->
    atom_to_binary(A, latin1);
to_binary(B) when is_binary(B) ->
    B;
to_binary(Bad) ->
    fail({bad_binary, Bad}).

-spec to_atom(term()) -> atom().
to_atom(B) when is_binary(B) ->
    try binary_to_atom(B, latin1)
    catch _:system_limit -> fail({bad_length, 255})
    end;
to_atom(A) when is_atom(A) ->
    A;
to_atom(Bad) ->
    fail({bad_atom, Bad}).

-spec to_existing_atom(term()) -> atom() | binary().
to_existing_atom(B) when is_binary(B) ->
    try binary_to_existing_atom(B, latin1)
    catch _:_ -> B
    end;
to_existing_atom(A) ->
    to_atom(A).

-spec to_string(term()) -> string().
to_string(A) when is_atom(A) ->
    atom_to_list(A);
to_string(S) ->
    binary_to_list(to_binary(S)).

-spec from_hex(binary()) -> binary().
from_hex(B) when (size(B) rem 2) == 0 ->
    << <<(hexchar_to_digit(Hi)*16 + hexchar_to_digit(Lo))>> || <<Hi, Lo>> <= B >>.

-spec hexchar_to_digit(char()) -> byte().
hexchar_to_digit(C) when C >= $0 andalso C =< $9 ->
    C - $0;
hexchar_to_digit(C) when C >= $a andalso C =< $f ->
    C - 87;
hexchar_to_digit(C) when C >= $A andalso C =< $F ->
    C - 55.

-spec to_int(term()) -> integer().
to_int(I) when is_integer(I) ->
    I;
to_int(Bad) ->
    fail({bad_int, Bad}).

-spec to_int(term(), infinity()) -> integer() | infinity().
to_int(I, _) when is_integer(I) -> I;
to_int(infinity, Inf) -> Inf;
to_int(infinite, Inf) -> Inf;
to_int(unlimited, Inf) -> Inf;
to_int(B, Inf) when is_binary(B) ->
    try binary_to_existing_atom(B, latin1) of
        A -> to_int(A, Inf)
    catch _:_ ->
            fail({bad_int, B})
    end;
to_int(Bad, _) ->
    fail({bad_int, Bad}).

-spec to_number(term()) -> number().
to_number(N) when is_number(N) ->
    N;
to_number(Bad) ->
    fail({bad_number, Bad}).

-spec to_timeout(term(), timeout_unit()) -> pos_integer() | infinity().
to_timeout(Term, Unit) ->
    to_timeout(Term, Unit, undefined).

-spec to_timeout(term(), timeout_unit(), infinity() | undefined) -> pos_integer() | infinity().
to_timeout(I, Unit, Inf) when is_integer(I) ->
    if I>0 -> to_ms(I, Unit);
       Inf == undefined -> fail({bad_pos_int, I});
       true -> fail({bad_pos_int, Inf, I})
    end;
to_timeout(A, Unit, Inf) when is_atom(A) ->
    to_timeout(atom_to_binary(A, latin1), Unit, Inf);
to_timeout(B, Unit, Inf) when is_binary(B) ->
    S = binary_to_list(B),
    case string:to_integer(S) of
        {error, _} when Inf /= undefined ->
            _ = (enum([infinite, infinity, unlimited]))(B),
            Inf;
        {error, _} ->
            fail({bad_int, B});
        {I, ""} when is_integer(I), I>0 ->
            to_ms(I, Unit);
        {I, [_|_] = Suffix} when is_integer(I), I>0 ->
            case timeout_unit(Suffix) of
                {ok, Unit1} -> to_ms(I, Unit1, Unit);
                error -> fail({bad_timeout_unit, Suffix})
            end;
        {I, _} when Inf == undefined ->
            fail({bad_pos_int, I});
        {I, _} ->
            fail({bad_pos_int, Inf, I})
    end;
to_timeout(Bad, _, Inf) when Inf == undefined ->
    fail({bad_timeout, Bad});
to_timeout(Bad, _, Inf) ->
    fail({bad_timeout, Inf, Bad}).

-spec to_ms(pos_integer(), timeout_unit()) -> pos_integer().
to_ms(I, Unit) ->
    case Unit of
        millisecond -> I;
        second -> timer:seconds(I);
        minute -> timer:minutes(I);
        hour -> timer:hours(I);
        day -> timer:hours(I*24)
    end.

-spec to_ms(pos_integer(), timeout_unit(), timeout_unit()) -> pos_integer().
to_ms(I, Unit, MinUnit) ->
    MSecs = to_ms(I, Unit),
    case MSecs >= to_ms(1, MinUnit) of
        true -> MSecs;
        false -> fail({bad_timeout_min, MinUnit})
    end.

-spec timeout_unit(string()) -> {ok, timeout_unit()} | error.
timeout_unit(S) ->
    U = string:strip(string:to_lower(S), both, $ ),
    if U == "ms"; U == "msec"; U == "msecs";
       U == "millisec"; U == "millisecs";
       U == "millisecond"; U == "milliseconds" ->
            {ok, millisecond};
       U == "s"; U == "sec"; U == "secs"; U == "second"; U == "seconds" ->
            {ok, second};
       U == "m"; U == "min"; U == "mins"; U == "minute"; U == "minutes" ->
            {ok, minute};
       U == "h"; U == "hour"; U == "hours" ->
            {ok, hour};
       U == "d"; U == "day"; U == "days" ->
            {ok, day};
       true ->
            error
    end.

-spec is_unicode(binary(), unicode:encoding()) -> boolean().
is_unicode(Bin, Encoding) ->
    try unicode:characters_to_list(Bin, Encoding) of
        L when is_list(L) -> true;
        _ -> false
    catch _:_ ->
            false
    end.

-spec unique(list(T), [proplists:property()]) -> list(T).
unique(L, Opts) ->
    case proplists:get_bool(unique, Opts) of
        true -> unique(L);
        false -> L
    end.

-spec unique(list(T)) -> list(T).
unique([{_, _}|_] = Map) ->
    lists:foldr(
      fun({K, V}, Acc) ->
              case lists:keymember(K, 1, Acc) of
                  true -> fail({duplicated_key, K});
                  false -> [{K, V}|Acc]
              end
      end, [], Map);
unique(L) ->
    lists:foldr(
      fun(X, Acc) ->
              case lists:member(X, Acc) of
                  true -> fail({duplicated_value, X});
                  false -> [X|Acc]
              end
      end, [], L).

-spec string_to_number(string()) -> number().
string_to_number(S) ->
    try erlang:list_to_integer(S) of
        Int -> Int
    catch _:badarg ->
            try erlang:list_to_float(S) of
                Float -> Float
            catch _:badarg ->
                    fail({bad_number, list_to_binary(S)})
            end
    end.

-spec parse_ip_netmask(string()) -> {ok, inet:ip4_address(), 0..32} |
                                    {ok, inet:ip6_address(), 0..128} |
                                    error.
parse_ip_netmask(S) ->
    case string:tokens(S, "/") of
        [IPStr] ->
            case inet:parse_address(IPStr) of
                {ok, {_, _, _, _} = IP} -> {ok, IP, 32};
                {ok, {_, _, _, _, _, _, _, _} = IP} -> {ok, IP, 128};
                _ -> error
            end;
        [IPStr, MaskStr] ->
            try list_to_integer(MaskStr) of
                Mask when Mask >= 0 ->
                    case inet:parse_address(IPStr) of
                        {ok, {_, _, _, _} = IP} when Mask =< 32 ->
                            {ok, IP, Mask};
                        {ok, {_, _, _, _, _, _, _, _} = IP} when Mask =< 128 ->
                            {ok, IP, Mask};
                        _ ->
                            error
                    end;
                _ ->
                    error
            catch _:_ ->
                    error
            end;
        _ ->
            error
    end.

-spec fail(error_reason()) -> no_return().
fail(Reason) ->
    erlang:nif_error({?MODULE, Reason, erase_ctx()}).

-spec prep_path(term()) -> binary().
prep_path(Path0) ->
    Path1 = (non_empty(binary()))(Path0),
    case filename:pathtype(Path1) of
        relative ->
            case file:get_cwd() of
                {ok, CWD} ->
                    filename:join(
                      unicode:characters_to_binary(CWD), Path1);
                {error, Reason} ->
                    fail({bad_cwd, Reason})
            end;
        _ ->
            Path1
    end.

-spec validate_options(list(), validators(), validator() | undefined,
                       [atom()], #{atom() => term()}, [atom()],
                       boolean(), return_type()) -> options().
validate_options(Opts, Validators, DefaultValidator,
                 Required, Defaults, Disallowed, CheckDups, Return) ->
    validate_options(Opts, Validators, DefaultValidator,
                     Required, Defaults, Disallowed, CheckDups, Return, []).

-spec validate_options(list(), validators(), validator() | undefined,
                       [atom()], #{atom() => term()}, [atom()], boolean(),
                       return_type(), options()) -> options().
validate_options([{O, Val}|Opts], Validators, DefaultValidator,
                 Required, Defaults, Disallowed, CheckDups, Return, Acc) ->
    Opt = to_existing_atom(O),
    case lists:member(Opt, Disallowed) of
        true -> fail({disallowed_option, Opt});
        false ->
            case maps:get(Opt, Validators, DefaultValidator) of
                undefined ->
                    % TODO: revisit this
                    ?LOG_WARNING("[yval] Unknown option: ~p", [Opt]),
                    validate_options(Opts, Validators, DefaultValidator,
                                     Required, Defaults, Disallowed,
                                     CheckDups, Return, Acc);
                Validator when is_atom(Opt) ->
                    case CheckDups andalso lists:keymember(Opt, 1, Acc) of
                        true -> fail({duplicated_option, Opt});
                        false ->
                            Required1 = proplists:delete(Opt, Required),
                            Acc1 = [{Opt, validate_option(Opt, Val, Validator)}|Acc],
                            validate_options(Opts, Validators, DefaultValidator,
                                             Required1, Defaults, Disallowed,
                                             CheckDups, Return, Acc1)
                    end;
                _ ->
                    validate_options(Opts, Validators, DefaultValidator,
                                     Required, Defaults, Disallowed,
                                     CheckDups, Return, Acc)
            end
    end;
validate_options([], _, _, [], Defaults, _, _, Return, Acc) ->
    case Return of
        list -> apply_defaults(lists:reverse(Acc), Defaults);
        map -> maps:merge(Defaults, maps:from_list(Acc));
        dict -> dict:from_list(apply_defaults(Acc, Defaults));
        orddict -> orddict:from_list(apply_defaults(Acc, Defaults))
    end;
validate_options([], _, _, [Required|_], _,  _, _, _, _) ->
    fail({missing_option, Required});
validate_options(Bad, _, _, _, _, _, _, _, _) ->
    fail({bad_map, Bad}).

-spec validate_option(atom(), yaml(), validator(T)) -> T.
validate_option(Opt, Val, Validator) ->
    Ctx = get_ctx(),
    put_ctx([Opt|Ctx]),
    Ret = Validator(Val),
    put_ctx(Ctx),
    Ret.

-spec apply_defaults([{atom(), T}], #{atom() => T}) -> [{atom(), T}].
apply_defaults(Opts, Defaults) ->
    case maps:size(Defaults) of
        0 -> Opts;
        _ ->
            Rest = lists:foldl(
                     fun({Opt, _}, Acc) ->
                             maps:remove(Opt, Acc)
                     end, Defaults, Opts),
            Opts ++ maps:to_list(Rest)
    end.

%%%===================================================================
%%% Mutable context processing
%%%===================================================================
-spec get_ctx() -> ctx().
get_ctx() ->
    case get(yval_ctx) of
        undefined -> [];
        Opts -> Opts
    end.

-spec put_ctx(ctx()) -> ok.
put_ctx(Opts) ->
    put(yval_ctx, Opts),
    ok.

-spec erase_ctx() -> ctx().
erase_ctx() ->
    case erase(yval_ctx) of
        Opts when is_list(Opts) -> lists:reverse(Opts);
        _ -> []
    end.

%%%===================================================================
%%% Copied from xmerl_regexp.erl to avoid xmerl dependency
%%%===================================================================
-spec sh_to_awk(string()) -> string().
sh_to_awk(Sh) -> "^(" ++ sh_to_awk_1(Sh).    %Fix the beginning

sh_to_awk_1([$*|Sh]) ->                %This matches any string
    ".*" ++ sh_to_awk_1(Sh);
sh_to_awk_1([$?|Sh]) ->                %This matches any character
    [$.|sh_to_awk_1(Sh)];
sh_to_awk_1([$[, $^, $]|Sh]) ->            %This takes careful handling
    "\\^" ++ sh_to_awk_1(Sh);
%% Must move '^' to end.
sh_to_awk_1("[^" ++ Sh) -> [$[|sh_to_awk_2(Sh, true)];
sh_to_awk_1("[!" ++ Sh) -> "[^" ++ sh_to_awk_2(Sh, false);
sh_to_awk_1([$[|Sh]) -> [$[|sh_to_awk_2(Sh, false)];
sh_to_awk_1([C|Sh]) ->
    %% Unspecialise everything else which is not an escape character.
    case sh_special_char(C) of
        true -> [$\\, C|sh_to_awk_1(Sh)];
        false -> [C|sh_to_awk_1(Sh)]
    end;
sh_to_awk_1([]) -> ")$".            %Fix the end

sh_to_awk_2([$]|Sh], UpArrow) -> [$]|sh_to_awk_3(Sh, UpArrow)];
                       sh_to_awk_2(Sh, UpArrow) -> sh_to_awk_3(Sh, UpArrow).

sh_to_awk_3([$]|Sh], true) -> "^]" ++ sh_to_awk_1(Sh);
sh_to_awk_3([$]|Sh], false) -> [$]|sh_to_awk_1(Sh)];
sh_to_awk_3([C|Sh], UpArrow) -> [C|sh_to_awk_3(Sh, UpArrow)];
sh_to_awk_3([], true) -> [$^|sh_to_awk_1([])];
sh_to_awk_3([], false) -> sh_to_awk_1([]).

%% Test if a character is a special character.
-spec sh_special_char(char()) -> boolean().
sh_special_char($|) -> true;
sh_special_char($*) -> true;
sh_special_char($+) -> true;
sh_special_char($?) -> true;
sh_special_char($() -> true;
sh_special_char($)) -> true;
sh_special_char($\\) -> true;
sh_special_char($^) -> true;
sh_special_char($$) -> true;
sh_special_char($.) -> true;
sh_special_char($[) -> true;
sh_special_char($]) -> true;
sh_special_char($") -> true;
sh_special_char(_C) -> false.
