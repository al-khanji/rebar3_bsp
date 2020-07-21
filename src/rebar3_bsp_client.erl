%%==============================================================================
%% A client for the Build Server Protocol using the STDIO transport
%%==============================================================================
-module(rebar3_bsp_client).

%%==============================================================================
%% Behaviours
%%==============================================================================
-behaviour(gen_server).
%% gen_server callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        ]).

%%==============================================================================
%% Exports
%%==============================================================================
%% Erlang API
-export([ start_link/0
        , stop/0
        ]).

%% Connection
-export([ get_connection/1
        ]).

%% Server Lifetime
-export([ build_initialize/1
        , build_initialized/1
        , build_shutdown/0
        , build_exit/0
        , build_show_message/1
        , build_log_message/1
        , build_publish_diagnostics/1
        ]).

%%==============================================================================
%% Includes
%%==============================================================================
-include("rebar3_bsp.hrl").

%%==============================================================================
%% Defines
%%==============================================================================
-define(SERVER, ?MODULE).
-define(TIMEOUT, infinity).

%%==============================================================================
%% Record Definitions
%%==============================================================================
-record(state, { request_id    = 1 :: request_id()
               , pending       = []
               , notifications = []
               , requests      = []
               , port          :: port()
               }).

%%==============================================================================
%% Type Definitions
%%==============================================================================
-type state()      :: #state{}.
-type request_id() :: pos_integer().
-type params()     :: #{}.
-type connection() :: #{}.

%%==============================================================================
%% Erlang API
%%==============================================================================
-spec start_link() -> {ok, pid()}.
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
  gen_server:stop(?SERVER).

%%==============================================================================
%% Connection
%%==============================================================================
-spec get_connection(uri()) -> {ok, connection()} | {error, not_found}.
get_connection(RootUri) ->
  RootPath = binary_to_list(els_uri:path(RootUri)),
  Candidates = filelib:wildcard(filename:join([RootPath, ".bsp", "*.json"])),
  case Candidates of
    [] ->
      {error, not_found};
    [C|_] ->
      {ok, Content} = file:read_file(C),
      {ok, jsx:decode(Content, [return_maps, {labels, atom}])}
  end.

%%==============================================================================
%% Server Lifetime
%%==============================================================================
-spec build_initialize(params()) -> map().
build_initialize(Params) ->
  gen_server:call(?SERVER, {build_initialize, Params}, ?TIMEOUT).

-spec build_initialized(params()) -> map().
build_initialized(Params) ->
  gen_server:call(?SERVER, {build_initialized, Params}).

-spec build_shutdown() -> map().
build_shutdown() ->
  gen_server:call(?SERVER, {shutdown}).

-spec build_exit() -> ok.
build_exit() ->
  gen_server:call(?SERVER, {exit}).

-spec build_show_message(params()) -> ok.
build_show_message(Params) ->
  gen_server:call(?SERVER, {build_show_message, Params}).

-spec build_log_message(params()) -> ok.
build_log_message(Params) ->
  gen_server:call(?SERVER, {build_log_message, Params}).

-spec build_publish_diagnostics(params()) -> ok.
build_publish_diagnostics(Params) ->
  gen_server:call(?SERVER, {build_publish_diagnostics, Params}).

%%==============================================================================
%% gen_server Callback Functions
%%==============================================================================
-spec init([]) -> {ok, state()}.
init([]) ->
  process_flag(trap_exit, true),
  E = os:find_executable("rebar3"),
  Port = open_port({spawn_executable, E}, [{args, ["bsp"]}, use_stdio, binary]),
  {ok, #state{port = Port}}.

-spec handle_call(any(), any(), state()) -> {reply, any(), state()}.
handle_call({build_initialized, Opts}, _From, #state{port = Port} = State) ->
  Method = method_lookup(build_initialized),
  Params = notification_params(Opts),
  Content = els_protocol:notification(Method, Params),
  send(Port, Content),
  {reply, ok, State};
handle_call({exit}, _From, #state{port = Port} = State) ->
  RequestId = State#state.request_id,
  Method = <<"exit">>,
  Params = #{},
  Content = els_protocol:request(RequestId, Method, Params),
  send(Port, Content),
  {reply, ok, State};
handle_call({shutdown}, From, #state{port = Port} = State) ->
  RequestId = State#state.request_id,
  Method = <<"shutdown">>,
  Params = #{},
  Content = els_protocol:request(RequestId, Method, Params),
  send(Port, Content),
  {noreply, State#state{ request_id = RequestId + 1
                       , pending    = [{RequestId, From} | State#state.pending]
                       }};
handle_call(Input = {build_initialize, _}, From, State) ->
  #state{ port = Port, request_id = RequestId } = State,
  Method = method_lookup(build_initialize),
  Params = request_params(Input),
  Content = els_protocol:request(RequestId, Method, Params),
  send(Port, Content),
  {noreply, State#state{ request_id = RequestId + 1
                       , pending    = [{RequestId, From} | State#state.pending]
                       }}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast({handle_responses, Responses}, State) ->
  #state{ pending = Pending0
        , notifications = Notifications0
        , requests = Requests0
        } = State,
  {Pending, Notifications, Requests}
    = do_handle_messages(Responses, Pending0, Notifications0, Requests0),
  {noreply, State#state{ pending = Pending
                       , notifications = Notifications
                       , requests = Requests
                       }};
handle_cast(_Request, State) ->
  {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(Request, State) ->
  lager:info("Request from port: ~p", [Request]),
  {noreply, State}.

%%==============================================================================
%% Internal Functions
%%==============================================================================
-spec do_handle_messages([map()], [any()], [any()], [any()]) ->
        {[any()], [any()], [any()]}.
do_handle_messages([], Pending, Notifications, Requests) ->
  {Pending, Notifications, Requests};
do_handle_messages([Message|Messages], Pending, Notifications, Requests) ->
  case is_response(Message) of
    true ->
      RequestId = maps:get(id, Message),
      lager:debug("[CLIENT] Handling Response [response=~p]", [Message]),
      case lists:keyfind(RequestId, 1, Pending) of
        {RequestId, From} ->
          gen_server:reply(From, Message),
          do_handle_messages( Messages
                            , lists:keydelete(RequestId, 1, Pending)
                            , Notifications
                            , Requests
                            );
        false ->
          do_handle_messages(Messages, Pending, Notifications, Requests)
      end;
    false ->
      case is_notification(Message) of
        true ->
          lager:debug( "[CLIENT] Discarding Notification [message=~p]"
                     , [Message]),
          do_handle_messages( Messages
                            , Pending
                            , [Message|Notifications]
                            , Requests);
        false ->
          lager:debug( "[CLIENT] Discarding Server Request [message=~p]"
                     , [Message]),
          do_handle_messages( Messages
                            , Pending
                            , Notifications
                            , [Message|Requests])
      end
  end.

-spec request_params(tuple()) -> any().
request_params({build_initialize, RootUri}) ->
  {ok, Vsn} = application:get_key(reba3_bsp, vsn),
  #{ <<"displayName">>  => <<"Rebar3 BSP Client">>
   , <<"version">>      => list_to_binary(Vsn)
   , <<"bspVersion">>   => <<"2.0.0">>
   , <<"rootUri">>      => RootUri
   , <<"capabilities">> => #{ <<"languageIds">> => [<<"erlang">>] }
   , <<"data">>         => #{}
   }.

-spec notification_params(tuple()) -> map().
notification_params({Uri}) ->
  TextDocument = #{ uri => Uri },
  #{textDocument => TextDocument};
notification_params({Uri, LanguageId, Version, Text}) ->
  TextDocument = #{ uri        => Uri
                  , languageId => LanguageId
                  , version    => Version
                  , text       => Text
                  },
  #{textDocument => TextDocument};
notification_params(_) ->
  #{}.

-spec is_notification(map()) -> boolean().
is_notification(#{id := _Id}) ->
  false;
is_notification(_) ->
  true.

-spec is_response(map()) -> boolean().
is_response(#{method := _Method}) ->
  false;
is_response(_) ->
  true.

-spec send(port(), binary()) -> ok.
send(Port, Payload) ->
  port_command(Port, Payload).

-spec method_lookup(atom()) -> binary().
method_lookup(build_initialize) -> <<"build/initialize">>;
method_lookup(build_initialized) -> <<"build/initialized">>.
